"""
Pydantic response models matching shot_scorer.py's output shape exactly.

Use these as FastAPI response_model= on your analysis endpoint. This gets
you:
  - Auto-generated, accurate Swagger/OpenAPI docs (/docs) showing every
    field, type, and nesting instead of a raw dict
  - Automatic validation that your endpoint actually returns what it claims
    to (FastAPI will error loudly in dev if a field is missing/mistyped,
    instead of silently shipping a broken response to Flutter)
  - Editor autocomplete on the Flutter/frontend side if you generate a
    matching Dart model from this schema later

USAGE:
    from shot_score_models import ShotAnalysisResponse

    @app.post("/analyze", response_model=ShotAnalysisResponse)
    async def analyze_shot(...):
        ...
        return result  # FastAPI validates + serializes against the model
"""

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Overlay / skeleton data
# ---------------------------------------------------------------------------

class JointPoint(BaseModel):
    x: float
    y: float
    z: float
    visibility: float


class OverlayFrame(BaseModel):
    frame: int
    time_sec: float
    landmarks: Dict[str, JointPoint]
    is_load_frame: bool
    is_release_frame: bool
    joint_status: Dict[str, str] = Field(
        description='Maps joint name -> "red" or "green" for skeleton overlay coloring'
    )


# ---------------------------------------------------------------------------
# Section / issue data
# ---------------------------------------------------------------------------

class Issue(BaseModel):
    metric: str
    frame: int
    time_sec: Optional[float] = None
    start_frame: int
    start_time_sec: Optional[float] = None
    end_frame: int
    end_time_sec: Optional[float] = None
    value: Optional[float] = None
    verdict: str
    deduction: float
    explanation: str
    fix: str


class Section(BaseModel):
    label: str
    score: Optional[float] = Field(
        None, description="Points earned in this section, or null if it couldn't be computed"
    )
    max_points: float
    issues: List[Issue] = Field(default_factory=list)


class Sections(BaseModel):
    feet_stance: Section
    knee_bend: Section
    ball_position: Section
    elbow_alignment: Section
    shooting_motion: Section
    follow_through: Section
    balance: Section


class Improvement(BaseModel):
    id: str = Field(
        description='Stable deterministic id, e.g. "elbow_alignment_01"'
    )
    section: str
    issue: str
    frame: int
    time_sec: Optional[float] = None
    start_frame: int
    start_time_sec: Optional[float] = None
    end_frame: int
    end_time_sec: Optional[float] = None
    severity: str = Field(description='"high", "medium", or "low"')
    explanation: str
    fix: str


# ---------------------------------------------------------------------------
# Supplementary diagnostic data (not part of the 7-section score)
# ---------------------------------------------------------------------------

class Tempo(BaseModel):
    dip_start_frame: Optional[int] = None
    dip_start_time_sec: Optional[float] = None
    load_frame: Optional[int] = None
    load_time_sec: Optional[float] = None
    release_frame: Optional[int] = None
    release_time_sec: Optional[float] = None
    dip_duration_sec: Optional[float] = None
    rise_duration_sec: Optional[float] = None
    total_duration_sec: Optional[float] = None
    release_wrist_angular_velocity_deg_per_sec: Optional[float] = None


class Rotation(BaseModel):
    shoulder_rotation_deg: Optional[float] = None
    hip_rotation_deg: Optional[float] = None
    note: str


# ---------------------------------------------------------------------------
# Flutter Results-card compatibility (from to_analyze_payload)
# ---------------------------------------------------------------------------

class BiomechanicsItem(BaseModel):
    category: str
    score: int
    status: str
    color: str
    issue: str
    correction: str
    measurement: str
    timestamp: str
    seconds: float
    confidence: float
    highlight: List[str] = Field(default_factory=list)
    phase: Optional[str] = None
    phase_key: Optional[str] = None


# ---------------------------------------------------------------------------
# Top-level response
# ---------------------------------------------------------------------------

class ShotAnalysisResult(BaseModel):
    """One scored shot — matches score_single_shot()'s return dict exactly."""
    shooting_side: str = Field(description='"left" or "right"')
    load_frame: Optional[int] = None
    release_frame: Optional[int] = None
    overall_score: Optional[float] = Field(
        None, description="0-100, or null if confidence was too low to trust a score"
    )
    confidence: float = Field(description="0-100, percent of metrics successfully computed")
    camera_view: str = Field(description='"front", "side", "45_degree", or "unknown"')
    metrics_computed: str = Field(description='e.g. "9/10"')
    unreliable_metrics: List[str] = Field(
        default_factory=list,
        description="Metrics skipped due to unreliable shoulder-width normalization",
    )
    sections: Sections
    strengths: List[str] = Field(default_factory=list)
    improvements: List[Improvement] = Field(default_factory=list)
    tempo: Tempo
    rotation: Rotation
    overlay_frames: List[OverlayFrame] = Field(default_factory=list)
    notes: str


class ShotAnalysisResponse(BaseModel):
    """Wraps one or more scored shots — matches shot_scorer.py's CLI/file output."""
    shots: List[ShotAnalysisResult]


# ---------------------------------------------------------------------------
# Optional: extended response including your app's video/processing metadata
# (video URLs, timings, upload info). Adjust field names to match your
# actual backend response — these are inferred from your earlier sample
# output and may not be exact.
# ---------------------------------------------------------------------------

class VideoFormat(BaseModel):
    width: int
    height: int
    aspect_ratio: str
    fps: int
    slow_motion_factor: Optional[float] = None


class ProcessingTimings(BaseModel):
    upload_save_s: float
    frame_extraction_s: float
    pose_detection_s: float
    scoring_s: float
    report_total_s: float


class AppShotAnalysisResponse(ShotAnalysisResult):
    """
    Single-shot response extended with app/video metadata. Use this instead
    of ShotAnalysisResult directly if your endpoint returns everything in
    one flat object rather than nested under "shots".
    """
    # Flutter Results compatibility (to_analyze_payload)
    biomechanics: List[BiomechanicsItem] = Field(default_factory=list)
    breakdown: List[BiomechanicsItem] = Field(default_factory=list)
    metrics: Dict[str, Any] = Field(default_factory=dict)
    issues: List[str] = Field(default_factory=list)
    recommendations: List[str] = Field(default_factory=list)
    improvement_summary: Optional[str] = None
    timeline: List[Any] = Field(default_factory=list)
    frame_metrics: List[Any] = Field(default_factory=list)
    frame_phases: List[Any] = Field(default_factory=list)
    phases: Dict[str, Any] = Field(default_factory=dict)
    scorer: Optional[str] = None
    step: Optional[int] = None

    # Media / pipeline metadata
    analysis_video: Optional[str] = None
    analysis_video_url: Optional[str] = None
    skeleton_video_url: Optional[str] = None
    slow_motion_video_url: Optional[str] = None
    original_video_url: Optional[str] = None
    shot_angles_url: Optional[str] = None
    shot_score_url: Optional[str] = None
    video_ready: Optional[bool] = None
    overlay_ready: Optional[bool] = None
    mediapipe_ok: Optional[bool] = None
    video_format: Optional[VideoFormat] = None
    timings: Optional[ProcessingTimings] = None
    frames_processed: Optional[int] = None
    frames_with_pose: Optional[int] = None
    pose_detection_rate: Optional[float] = None
    fps: Optional[float] = None
    filename: Optional[str] = None
    size: Optional[int] = None
    received: Optional[bool] = None
    temp_media_id: Optional[str] = None
    storage_policy: Optional[str] = None


# ---------------------------------------------------------------------------
# Example FastAPI wiring (for reference — adapt to your actual app structure)
# ---------------------------------------------------------------------------
"""
from fastapi import FastAPI, UploadFile
from shot_score_models import AppShotAnalysisResponse

app = FastAPI()

@app.post("/analyze", response_model=AppShotAnalysisResponse, summary="Analyze a shot video")
async def analyze_shot(video: UploadFile):
    '''
    Uploads a shot video, runs pose extraction + scoring, and returns the
    full analysis: 7-section score, per-issue playback ranges (start_frame/
    end_frame), tempo, rotation, and skeleton overlay data.
    '''
    # ... your existing pipeline ...
    return result
"""
