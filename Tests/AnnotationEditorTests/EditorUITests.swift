import Testing

/// Suites that build real editor windows run one test at a time: AppKit window,
/// first-responder and text-input state is process-wide.
@Suite(.serialized) enum EditorUITests {}
