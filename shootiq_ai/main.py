"""ShootIQ AI backend — FastAPI entrypoint (Step 5 biomechanics + report path)."""

from __future__ import annotations

import shutil
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Optional

import json

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

from biomechanics_engine import analyze_biomechanics
from follow_through_analyzer import enrich_biomechanics_with_angle_analysis
from pose_pipeline import (
    PROCESSED_VIDEOS_DIR,
    POSE_SAMPLE_EVERY,
    render_overlay_from_saved_pose,
    run_pose_detection,
)
from video_pipeline import (
    SLOW_MOTION_FACTOR,
    TARGET_HEIGHT,
    TARGET_WIDTH,
    make_slow_motion,
    standardize_vertical,
)

app = FastAPI(
    title="ShootIQ AI",
    description="Basketball shot pose detection, skeleton overlay, and mechanics",
    version="0.10.0-step5",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ALLOWED_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v"}
BASE_DIR = Path(__file__).resolve().parent
UPLOADS_DIR = BASE_DIR / "uploads"
UPLOADS_DIR.mkdir(exist_ok=True)
PROCESSED_VIDEOS_DIR.mkdir(parents=True, exist_ok=True)

# Temp server copies are deleted after analysis (or on /cleanup).
TEMP_MEDIA_TTL_S = 30 * 60


def _safe_unlink(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError as exc:
        print(f"Temp cleanup warning ({path}): {exc}")


def _safe_rmtree(path: Path) -> None:
    try:
        if path.exists() and path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
    except OSError as exc:
        print(f"Temp dir cleanup warning ({path}): {exc}")


def cleanup_temp_media(stem: str) -> dict[str, Any]:
    """Delete temporary upload + processed artifacts for a single analysis stem."""
    if not stem or "/" in stem or "\\" in stem or ".." in stem:
        raise HTTPException(status_code=400, detail="Invalid temp media id")

    removed: list[str] = []

    for upload in UPLOADS_DIR.glob(f"{stem}*"):
        if upload.is_file():
            _safe_unlink(upload)
            removed.append(str(upload))

    for name in (
        f"{stem}_vertical.mp4",
        f"{stem}_analysis.mp4",
        f"{stem}_analysis_slow.mp4",
    ):
        path = PROCESSED_VIDEOS_DIR / name
        if path.exists():
            _safe_unlink(path)
            removed.append(str(path))

    pose_run = PROCESSED_VIDEOS_DIR / "pose_runs" / stem
    if pose_run.exists():
        _safe_rmtree(pose_run)
        removed.append(str(pose_run))

    print(f"TEMP MEDIA CLEANUP stem={stem} removed={len(removed)}")
    return {"temp_media_id": stem, "removed": removed, "ok": True}


def _schedule_delayed_cleanup(stem: str, delay_s: int = TEMP_MEDIA_TTL_S) -> None:
    """Safety net if the Flutter client never calls /cleanup."""

    def _run() -> None:
        time.sleep(delay_s)
        try:
            cleanup_temp_media(stem)
        except Exception as exc:  # noqa: BLE001
            print(f"Delayed cleanup failed for {stem}: {exc}")

    threading.Thread(
        target=_run,
        daemon=True,
        name=f"cleanup-{stem}",
    ).start()


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "service": "shootiq_ai",
        "step": "step5_biomechanics",
        "pose_sample_every": POSE_SAMPLE_EVERY,
        "version": app.version,
        "video_storage": "temporary_only",
        "scorer": "biomechanics_engine",
    }


@app.delete("/cleanup/{stem}")
def cleanup_temp_media_endpoint(stem: str) -> dict[str, Any]:
    """Delete temporary server copies after the client saved results locally."""
    return cleanup_temp_media(stem)


@app.post("/upload-test")
async def upload_test(file: UploadFile = File(...)) -> dict[str, str]:
    filename = Path(file.filename or "shot.mp4").name
    save_path = UPLOADS_DIR / filename
    with open(save_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"filename": filename, "saved_location": str(save_path)}


@app.get("/processed/{file_path:path}")
def get_processed_video(file_path: str) -> FileResponse:
    """Serve processed media / pose JSON under processed_videos/ (path-safe)."""
    candidate = (PROCESSED_VIDEOS_DIR / file_path).resolve()
    root = PROCESSED_VIDEOS_DIR.resolve()
    if root not in candidate.parents and candidate != root:
        raise HTTPException(status_code=404, detail="Processed file not found")
    if not candidate.exists() or not candidate.is_file():
        raise HTTPException(status_code=404, detail="Processed file not found")

    media_type = "application/json" if candidate.suffix.lower() == ".json" else "video/mp4"
    return FileResponse(
        candidate,
        media_type=media_type,
        filename=candidate.name,
        headers={
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=600",
        },
    )


def _render_overlay_background(
    standardized_path: Path,
    stem: str,
    overlay_path: Path,
    slow_path: Path,
    pose_run_dir: Path,
) -> None:
    """Render Step-4 basic skeleton + slow-mo AFTER the report is returned."""
    try:
        t0 = time.perf_counter()
        print(f"Background overlay start: {standardized_path}")
        existing = pose_run_dir / "skeleton_overlay.mp4"
        if existing.exists() and existing.stat().st_size > 0:
            shutil.copy2(existing, overlay_path)
        else:
            produced = render_overlay_from_saved_pose(
                standardized_path,
                pose_run_dir,
            )
            if produced and produced.exists():
                shutil.copy2(produced, overlay_path)
            else:
                result = run_pose_detection(
                    video_path=standardized_path,
                    output_dir=pose_run_dir,
                    sample_every=POSE_SAMPLE_EVERY,
                    write_overlay=True,
                )
                produced2 = Path(result["skeleton_overlay"] or "")
                if produced2.exists():
                    shutil.copy2(produced2, overlay_path)

        if overlay_path.exists():
            make_slow_motion(overlay_path, slow_path, factor=SLOW_MOTION_FACTOR)
        print(
            f"Background overlay completed ({time.perf_counter() - t0:.2f}s) "
            f"overlay={overlay_path.exists()} slow={slow_path.exists()}"
        )
    except Exception as exc:  # noqa: BLE001
        print("Background overlay ERROR:", exc)


async def _read_upload(
    file: Optional[UploadFile],
    video: Optional[UploadFile],
) -> tuple[str, bytes, Path]:
    upload = file or video
    if upload is None:
        raise HTTPException(
            status_code=422,
            detail="Missing upload field. Send multipart form field `file` or `video`.",
        )

    original_name = Path(upload.filename or "shot.mp4").name
    suffix = Path(original_name).suffix.lower() or ".mp4"
    if suffix not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported video type '{suffix}'. Use mp4/mov/etc.",
        )

    contents = await upload.read()
    print("VIDEO NAME:", original_name)
    print("VIDEO SIZE:", len(contents))
    if not contents:
        raise HTTPException(status_code=400, detail="Uploaded video is empty")

    stem = f"{Path(original_name).stem}_{uuid.uuid4().hex[:8]}"
    temp_path = UPLOADS_DIR / f"{stem}{suffix}"
    temp_path.write_bytes(contents)
    print(f"VIDEO SAVED: {temp_path}")
    return original_name, contents, temp_path


@app.post("/analyze-pose")
async def analyze_pose_only(
    request: Request,
    file: Optional[UploadFile] = File(None),
    video: Optional[UploadFile] = File(None),
) -> dict:
    """Step 4 foundation endpoint — MediaPipe Pose only."""
    original_name, contents, temp_path = await _read_upload(file, video)
    stem = temp_path.stem
    pose_run_dir = PROCESSED_VIDEOS_DIR / "pose_runs" / stem

    try:
        standardized_path = PROCESSED_VIDEOS_DIR / f"{stem}_vertical.mp4"
        standardize_vertical(temp_path, standardized_path)
        pose_result = run_pose_detection(
            video_path=standardized_path,
            output_dir=pose_run_dir,
            sample_every=POSE_SAMPLE_EVERY,
            write_overlay=True,
        )
    except Exception as exc:  # noqa: BLE001
        print("ANALYZE-POSE ERROR:", exc)
        raise HTTPException(status_code=500, detail=f"Pose detection failed: {exc}") from exc
    finally:
        _safe_unlink(temp_path)

    host = request.headers.get("host")
    base = f"{request.url.scheme}://{host}".rstrip("/") if host else str(request.base_url).rstrip("/")

    public_overlay = PROCESSED_VIDEOS_DIR / f"{stem}_analysis.mp4"
    skeleton_src = Path(pose_result["skeleton_overlay"] or "")
    if skeleton_src.exists():
        shutil.copy2(skeleton_src, public_overlay)

    _schedule_delayed_cleanup(stem)

    return {
        "step": 4,
        "mediapipe_ok": pose_result["mediapipe_ok"],
        "frames_processed": pose_result["frames_processed"],
        "frames_sampled": pose_result["frames_sampled"],
        "frames_with_pose": pose_result["frames_with_pose"],
        "pose_sample_every": pose_result["pose_sample_every"],
        "pose_detection_rate": pose_result["pose_detection_rate"],
        "tracked": pose_result["tracked"],
        "landmarks": pose_result["landmarks"],
        "pose_frames": pose_result["pose_frames"][:40],
        "pose_frames_total": len(pose_result["pose_frames"]),
        "original_video_url": f"{base}/processed/{standardized_path.name}",
        "skeleton_video_url": f"{base}/processed/{public_overlay.name}",
        "pose_data_url": f"{base}/processed/pose_runs/{stem}/pose_data.json",
        "shot_angles_url": f"{base}/processed/pose_runs/{stem}/shot_angles.json",
        "follow_through_analysis_url": (
            f"{base}/processed/pose_runs/{stem}/follow_through_analysis.json"
        ),
        "follow_through_analysis": pose_result.get("follow_through_analysis") or {},
        "output_dir": pose_result["output_dir"],
        "filename": original_name,
        "size": len(contents),
        "received": True,
        "temp_media_id": stem,
        "storage_policy": "temporary_ai_only",
    }


@app.post("/analyze")
async def analyze(
    request: Request,
    file: Optional[UploadFile] = File(None),
    video: Optional[UploadFile] = File(None),
    personal_baseline: Optional[str] = Form(None),
    dominant_hand: Optional[str] = Form(None),
) -> dict:
    """
    Analyze a basketball shot (pre-v4 biomechanics engine):
    1) save upload
    2) resize to 720p30 vertical
    3) MediaPipe Pose foundation (landmarks + pose_data.json)
    4) biomechanics report
    5) skeleton overlay continues in background
    """
    pipeline_t0 = time.perf_counter()
    timings: dict[str, float] = {}

    original_name, contents, temp_path = await _read_upload(file, video)
    stem = temp_path.stem
    timings["upload_save_s"] = 0.0

    try:
        t_extract = time.perf_counter()
        standardized_path = PROCESSED_VIDEOS_DIR / f"{stem}_vertical.mp4"
        standardize_vertical(temp_path, standardized_path)
        timings["frame_extraction_s"] = round(time.perf_counter() - t_extract, 3)
    except Exception as exc:  # noqa: BLE001
        print("STANDARDIZE ERROR:", exc)
        _safe_unlink(temp_path)
        raise HTTPException(
            status_code=500,
            detail=f"Video standardize failed: {exc}",
        ) from exc
    finally:
        _safe_unlink(temp_path)

    pose_run_dir = PROCESSED_VIDEOS_DIR / "pose_runs" / stem
    try:
        t_pose = time.perf_counter()
        pose_result = run_pose_detection(
            video_path=standardized_path,
            output_dir=pose_run_dir,
            sample_every=POSE_SAMPLE_EVERY,
            write_overlay=False,
        )
        timings["pose_detection_s"] = round(time.perf_counter() - t_pose, 3)
    except Exception as exc:  # noqa: BLE001
        print("POSE ERROR:", exc)
        raise HTTPException(
            status_code=500,
            detail=f"Pose detection failed: {exc}",
        ) from exc

    baseline_obj: dict[str, Any] | None = None
    if personal_baseline:
        try:
            parsed = json.loads(personal_baseline)
            if isinstance(parsed, dict):
                baseline_obj = parsed
        except json.JSONDecodeError:
            print("personal_baseline JSON ignored (invalid)")

    # User's own declared shooting hand, when available, beats auto-detection
    # from wrist visibility — that heuristic is unreliable when the camera
    # sits on the side opposite the shooting hand, since that arm is
    # partially occluded through the whole clip.
    shooting_hand_override = None
    if dominant_hand and dominant_hand.strip().lower() in ("left", "right"):
        shooting_hand_override = dominant_hand.strip().lower()
    print(f"dominant_hand received={dominant_hand!r} -> override={shooting_hand_override!r}")

    try:
        t_score = time.perf_counter()
        mechanics = analyze_biomechanics(
            {
                "frames": pose_result.get("pose_frames")
                or pose_result.get("all_landmarks", []),
                "sample_every": pose_result.get("pose_sample_every")
                or pose_result.get("sample_every")
                or 1,
                "fps": float(pose_result.get("fps") or 30.0),
            },
            fps=float(pose_result.get("fps") or 30.0),
            personal_baseline=baseline_obj,
            sample_every=int(
                pose_result.get("pose_sample_every")
                or pose_result.get("sample_every")
                or 1
            ),
            shooting_hand_override=shooting_hand_override,
        )
        fta = pose_result.get("follow_through_analysis") or {}
        if fta:
            enriched = enrich_biomechanics_with_angle_analysis(
                mechanics.get("biomechanics") or [],
                fta,
            )
            mechanics["biomechanics"] = enriched
            mechanics["breakdown"] = enriched
            mechanics["follow_through_analysis"] = fta
        timings["scoring_s"] = round(time.perf_counter() - t_score, 3)
        print(
            f"Scoring completed ({timings['scoring_s']}s) "
            f"overall={mechanics.get('overall_score')}"
        )
    except Exception as exc:  # noqa: BLE001
        print("MECHANICS ERROR:", exc)
        raise HTTPException(
            status_code=500,
            detail=f"Shooting mechanics failed: {exc}",
        ) from exc

    host = request.headers.get("host")
    if host:
        base = f"{request.url.scheme}://{host}".rstrip("/")
    else:
        base = str(request.base_url).rstrip("/")
    standardized_url = f"{base}/processed/{standardized_path.name}"
    overlay_name = f"{stem}_analysis.mp4"
    slow_name = f"{stem}_analysis_slow.mp4"
    overlay_path = PROCESSED_VIDEOS_DIR / overlay_name
    slow_path = PROCESSED_VIDEOS_DIR / slow_name
    overlay_url = f"{base}/processed/{overlay_name}"
    slow_url = f"{base}/processed/{slow_name}"

    threading.Thread(
        target=_render_overlay_background,
        args=(standardized_path, stem, overlay_path, slow_path, pose_run_dir),
        daemon=True,
        name=f"overlay-{stem}",
    ).start()
    print("Overlay render started in background (not blocking report)")

    _schedule_delayed_cleanup(stem)

    timings["report_total_s"] = round(time.perf_counter() - pipeline_t0, 3)
    print(f"Report generated ({timings['report_total_s']}s) timings={timings}")

    response = {
        "overall_score": mechanics["overall_score"],
        "metrics": mechanics["metrics"],
        "biomechanics": mechanics.get("biomechanics", []),
        "breakdown": mechanics.get("breakdown", mechanics.get("biomechanics", [])),
        "timeline": mechanics.get("timeline", []),
        "frame_metrics": mechanics.get("frame_metrics", []),
        "frame_phases": mechanics.get("frame_phases", []),
        "phase_detector": mechanics.get("phase_detector", {}),
        "phases": mechanics.get("phases", {}),
        "baseline_features": mechanics.get("baseline_features", {}),
        "measurement_confidence": mechanics.get("measurement_confidence", {}),
        "phase_landmarks": mechanics.get("phase_landmarks", {}),
        "personalization": mechanics.get("personalization", {}),
        "strengths": mechanics.get("strengths", []),
        "issues": mechanics["issues"],
        "recommendations": mechanics["recommendations"],
        "improvement_summary": mechanics.get(
            "improvement_summary",
            "Review your shot mechanics",
        ),
        "analysis_video": str(standardized_path),
        "analysis_video_url": standardized_url,
        "skeleton_video_url": overlay_url,
        "slow_motion_video_url": slow_url,
        "original_video_url": standardized_url,
        "pose_data_url": f"{base}/processed/pose_runs/{stem}/pose_data.json",
        "shot_angles_url": f"{base}/processed/pose_runs/{stem}/shot_angles.json",
        "follow_through_analysis_url": (
            f"{base}/processed/pose_runs/{stem}/follow_through_analysis.json"
        ),
        "follow_through_analysis": mechanics.get("follow_through_analysis")
        or pose_result.get("follow_through_analysis")
        or {},
        "video_ready": True,
        "overlay_ready": False,
        "mediapipe_ok": pose_result.get("mediapipe_ok", False),
        "video_format": {
            "width": TARGET_WIDTH,
            "height": TARGET_HEIGHT,
            "aspect_ratio": "9:16",
            "fps": 30,
            "slow_motion_factor": SLOW_MOTION_FACTOR,
        },
        "timings": timings,
        "frames_processed": pose_result["frames_processed"],
        "frames_with_pose": pose_result["frames_with_pose"],
        "pose_inferences": pose_result.get("frames_sampled"),
        "pose_sample_every": pose_result.get("pose_sample_every"),
        "pose_detection_rate": pose_result["pose_detection_rate"],
        "landmarks": pose_result.get("landmarks", {}),
        "received": True,
        "filename": original_name,
        "size": len(contents),
        "step": 5,
        "temp_media_id": stem,
        "storage_policy": "temporary_ai_only",
        "scorer": "biomechanics_engine",
    }
    print(
        "ANALYZE OK score=",
        response["overall_score"],
        "report_s=",
        timings["report_total_s"],
        "posed_frames=",
        pose_result.get("frames_with_pose"),
        "mediapipe_ok=",
        pose_result.get("mediapipe_ok"),
        "biomechanics=",
        [
            (b.get("category"), b.get("score"), b.get("color"))
            for b in response.get("biomechanics", [])
        ],
    )
    return response


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
