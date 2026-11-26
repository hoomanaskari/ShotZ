import ShotzCore

/// Builds `/usr/sbin/screencapture` arguments (ARCHITECTURE §3). Pure; unit-tested.
enum ScreencaptureArguments {
    /// - Parameter displayNumber: 1-based `-D` index for fullscreen captures.
    static func make(
        mode: CaptureMode, options: CaptureOptions, displayNumber: Int, outputPath: String
    ) -> [String] {
        var args: [String] = []
        switch mode {
        case .area: args += ["-i"]
        case .window: args += ["-i", "-W"]
        case .allInOne: args += ["-i", "-U"]
        case .fullscreen: args += ["-D", String(displayNumber)]
        }
        if !options.includeWindowShadow { args.append("-o") }
        if !options.playSound { args.append("-x") }
        args += ["-t", "png", outputPath]
        return args
    }
}
