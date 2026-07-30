class HelpFaqItem {
  const HelpFaqItem({required this.question, required this.answer});
  final String question;
  final String answer;
}

class HelpFaqSection {
  const HelpFaqSection({
    required this.title,
    required this.iconName,
    required this.items,
  });

  final String title;
  final String iconName;
  final List<HelpFaqItem> items;
}

abstract final class HelpFaqContent {
  static const sections = <HelpFaqSection>[
    HelpFaqSection(
      title: 'Getting Started',
      iconName: 'rocket',
      items: [
        HelpFaqItem(
          question: 'How do I analyze my first shot?',
          answer:
              'From Home or Analyze, choose Record or Upload a basketball shot video. After review, ShootIQ runs AI analysis and shows your score breakdown, issues, and coaching tips.',
        ),
        HelpFaqItem(
          question: 'Do I need an account?',
          answer:
              'Yes. Sign up with email to save your profile, preferences, and subscription status. Shot videos stay on your device.',
        ),
        HelpFaqItem(
          question: 'What devices are supported?',
          answer:
              'ShootIQ is designed for iPhone and also runs on macOS for development and practice. Use a device with a working camera or photo library for best results.',
        ),
      ],
    ),
    HelpFaqSection(
      title: 'Recording Tips',
      iconName: 'videocam',
      items: [
        HelpFaqItem(
          question: 'How should I frame my shot?',
          answer:
              'Film from the side or slight angle so your full body, ball, and rim are visible. Keep the camera steady, use good lighting, and avoid extreme zoom.',
        ),
        HelpFaqItem(
          question: 'How long should my clip be?',
          answer:
              'Short clips that capture the full shooting motion work best — typically a few seconds covering load, release, and follow-through.',
        ),
        HelpFaqItem(
          question: 'Can I upload from my camera roll?',
          answer:
              'Yes. Use Upload, select a video, preview it, then start analysis. The original file remains on your device.',
        ),
      ],
    ),
    HelpFaqSection(
      title: 'AI Analysis',
      iconName: 'psychology',
      items: [
        HelpFaqItem(
          question: 'What does AI analysis measure?',
          answer:
              'ShootIQ estimates mechanics such as feet/stance, knee bend, elbow alignment, release timing, balance, and follow-through, then returns coaching priorities.',
        ),
        HelpFaqItem(
          question: 'Are videos stored in the cloud forever?',
          answer:
              'No. Videos stay on your device by default. Temporary copies used for AI processing are deleted after analysis. Scores and feedback are saved locally.',
        ),
        HelpFaqItem(
          question: 'Why did analysis fail?',
          answer:
              'Common causes: AI server offline, poor connectivity, empty/corrupt video, or no clear pose detected. Check your connection and try a clearer clip.',
        ),
      ],
    ),
    HelpFaqSection(
      title: 'Understanding Scores',
      iconName: 'score',
      items: [
        HelpFaqItem(
          question: 'What does the overall score mean?',
          answer:
              'Overall score summarizes weighted mechanics categories. Higher scores mean closer alignment to healthy shooting patterns measured by the model — not a guarantee of makes.',
        ),
        HelpFaqItem(
          question: 'How should I use priority improvements?',
          answer:
              'Focus on the top 1–2 priorities first. Small consistent corrections usually improve consistency faster than changing everything at once.',
        ),
        HelpFaqItem(
          question: 'Can scores vary between takes?',
          answer:
              'Yes. Angle, lighting, clothing, and shot variation can change readings. Compare trends across many takes rather than one clip.',
        ),
      ],
    ),
    HelpFaqSection(
      title: 'Subscription',
      iconName: 'star',
      items: [
        HelpFaqItem(
          question: 'What plans are available?',
          answer:
              'Weekly (\$4.99), Monthly (\$14.99), and Yearly (\$59.99). Yearly includes a 3-day free trial. Monthly and Weekly bill immediately.',
        ),
        HelpFaqItem(
          question: 'How do I cancel?',
          answer:
              'Open Manage Subscription in ShootIQ, or cancel in your Apple ID / Google Play subscription settings before renewal.',
        ),
        HelpFaqItem(
          question: 'What is Restore Purchases?',
          answer:
              'Use Restore Purchases after reinstalling or switching devices to recover an existing store subscription entitlement.',
        ),
      ],
    ),
    HelpFaqSection(
      title: 'Account',
      iconName: 'person',
      items: [
        HelpFaqItem(
          question: 'How do I update my profile?',
          answer:
              'Go to Profile → edit your details, or Settings → Profile Information.',
        ),
        HelpFaqItem(
          question: 'How do I download my data?',
          answer:
              'Settings → Data & Export → Download My Data. Shot videos remain local unless a future export option includes them.',
        ),
        HelpFaqItem(
          question: 'How do I delete my account?',
          answer:
              'Settings → Privacy Controls → Delete Account. Local videos on your device are not automatically removed.',
        ),
      ],
    ),
    HelpFaqSection(
      title: 'Troubleshooting',
      iconName: 'build',
      items: [
        HelpFaqItem(
          question: 'Camera will not open',
          answer:
              'Confirm ShootIQ has Camera permission in device Settings. Force quit and reopen the app, then try again.',
        ),
        HelpFaqItem(
          question: 'I am stuck on Premium',
          answer:
              'If you already subscribed, open Restore Purchases or Manage Subscription. Active trial and paid plans unlock analysis.',
        ),
        HelpFaqItem(
          question: 'History is missing shots',
          answer:
              'Shot history is stored on-device. Reinstalling without a backup can clear local history. Export Shot History regularly if you need a copy.',
        ),
      ],
    ),
  ];
}
