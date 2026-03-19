class PostAnswerDtmfStep {
  const PostAnswerDtmfStep({
    required this.digit,
    required this.delaySeconds,
  });

  final String digit;
  final int delaySeconds;
}

const defaultPostAnswerDtmfSteps = <PostAnswerDtmfStep>[];

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.apiOrigin = 'https://example.com',
    this.apiReferer = 'https://example.com/',
    this.visaClientHeaderValue = '1',
    this.senderFilters = const <String>[],
    this.autoHandleEnabled = false,
    this.autoAnswerNumbers = const <String>[],
    this.autoHangUpDelaySeconds = 20,
    this.postAnswerDtmfSteps = defaultPostAnswerDtmfSteps,
  });

  final String apiBaseUrl;
  final String apiOrigin;
  final String apiReferer;
  final String visaClientHeaderValue;
  final List<String> senderFilters;
  final bool autoHandleEnabled;
  final List<String> autoAnswerNumbers;
  final int autoHangUpDelaySeconds;
  final List<PostAnswerDtmfStep> postAnswerDtmfSteps;

  bool get hasAutoAnswerNumbers =>
      autoAnswerNumbers.any((number) => number.trim().isNotEmpty);

  bool get shouldAutoHandleCalls => autoHandleEnabled && hasAutoAnswerNumbers;

  AppConfig copyWith({
    String? apiBaseUrl,
    String? apiOrigin,
    String? apiReferer,
    String? visaClientHeaderValue,
    List<String>? senderFilters,
    bool? autoHandleEnabled,
    List<String>? autoAnswerNumbers,
    int? autoHangUpDelaySeconds,
    List<PostAnswerDtmfStep>? postAnswerDtmfSteps,
  }) {
    return AppConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiOrigin: apiOrigin ?? this.apiOrigin,
      apiReferer: apiReferer ?? this.apiReferer,
      visaClientHeaderValue: visaClientHeaderValue ?? this.visaClientHeaderValue,
      senderFilters: senderFilters ?? this.senderFilters,
      autoHandleEnabled: autoHandleEnabled ?? this.autoHandleEnabled,
      autoAnswerNumbers: autoAnswerNumbers ?? this.autoAnswerNumbers,
      autoHangUpDelaySeconds:
          autoHangUpDelaySeconds ?? this.autoHangUpDelaySeconds,
      postAnswerDtmfSteps: postAnswerDtmfSteps ?? this.postAnswerDtmfSteps,
    );
  }
}

const defaultAppConfig = AppConfig(
  apiBaseUrl: 'https://example.com/api',
  apiOrigin: 'https://example.com',
  apiReferer: 'https://example.com/',
  visaClientHeaderValue: '1',
  senderFilters: <String>[],
  autoHandleEnabled: false,
  autoAnswerNumbers: <String>[],
  autoHangUpDelaySeconds: 20,
  postAnswerDtmfSteps: defaultPostAnswerDtmfSteps,
);