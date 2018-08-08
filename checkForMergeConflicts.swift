#! /usr/bin/env swift

import Foundation

// MARK: - Customize the definitions below

let remote = "origin"
let defaultBranch = "master"
let mergeTimeWarningUpperBound: TimeInterval = 2.0

struct Branch: Hashable {
    let name: String
    let target: String
    init(name: String, target: String = defaultBranch) {
        self.name = name
        self.target = target
    }
}

let branches: [Branch] = [
    Branch(name: "<#my-fancy-branch#>"),
    Branch(name: "<#my-urgent-hotfix#>", target: "<#release-branch#>")
]

// MARK: - End of customizable section

enum LogColor: Int {
    // https://github.com/mtynior/ColorizeSwift/blob/master/Source/ColorizeSwift.swift
    case black = 0
    case red = 31
    case green = 32
    case yellow = 33
    case blue = 34
    
    var terminalString: String {
        return "\u{001B}[\(self.rawValue)m"
    }
}

func log(_ message: String, color: LogColor = .blue) {
    print("\(color.terminalString)==> \(message)\(LogColor.black.terminalString)")
}

struct ProcessCompletionInfo {
    let exitStatus: Int32
    let executionTime: TimeInterval
}

func run(gitCommand args: String) -> ProcessCompletionInfo {
    // https://stackoverflow.com/a/26973384
    let command = "git " + args
    log(command)
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = command.split(separator: " ").map { String($0) }
    let startTime = Date()
    task.launch()
    task.waitUntilExit()
    let executionTime = Date().timeIntervalSince(startTime)
    let completionInfo = ProcessCompletionInfo(exitStatus: task.terminationStatus, executionTime: executionTime)
    return completionInfo
}

func run(gitCommand args: String, andFailWithDescriptionIfNeeded description: String) {
    let completionInfo = run(gitCommand: args)
    let exitStatus = completionInfo.exitStatus
    guard exitStatus == 0 else {
        log("\(description) failed with exit status \(exitStatus)")
        exit(exitStatus)
    }
}

enum MergeResult {
    case succeeded
    case tookALongTime
    case failed
}

var mergeResults = [Branch : MergeResult]()

run(gitCommand: "fetch --jobs=5 --recurse-submodules", andFailWithDescriptionIfNeeded: "Fetch")

var testsComplete: Int = 0
for branch in branches {
    run(gitCommand: "checkout --detach \(branch.name)", andFailWithDescriptionIfNeeded: "Checkout detached HEAD at \(branch.name)")
    run(gitCommand: "merge --ff-only origin/\(branch.name)", andFailWithDescriptionIfNeeded: "Merge origin/\(branch.name) (fast-forward only) to check for new commits on the remote")
    let mergeCompletionInfo = run(gitCommand: "merge --no-edit origin/\(branch.target)")
    if mergeCompletionInfo.exitStatus != 0 {
        log("Merge conflict detected: \(branch.name) --> \(branch.target)", color: .red)
        mergeResults[branch] = .failed
        run(gitCommand: "merge --abort", andFailWithDescriptionIfNeeded: "Merge abort")
    } else if mergeCompletionInfo.executionTime > mergeTimeWarningUpperBound {
        log("Merge took \(mergeCompletionInfo.executionTime) seconds, exceeding warning threshold of \(mergeTimeWarningUpperBound) seconds", color: .yellow)
        mergeResults[branch] = .tookALongTime
    } else {
        mergeResults[branch] = .succeeded
    }
    testsComplete += 1
    log("Tested \(testsComplete) of \(branches.count) merges...")
}

let conflicts = branches.filter { mergeResults[$0] == .failed }

let firstBranchWithConflicts: Branch? = conflicts.first
let branchToResetTo = firstBranchWithConflicts?.name ?? defaultBranch
run(gitCommand: "checkout \(branchToResetTo)", andFailWithDescriptionIfNeeded: "Checkout \(branchToResetTo)")
run(gitCommand: "submodule update --init --recursive", andFailWithDescriptionIfNeeded: "Submodule update")

log("")
log("Results:")
for branch in branches {
    let color: LogColor
    let glyph: String
    switch mergeResults[branch, default: .failed] {
    case .succeeded:
        color = .green
        glyph = "\u{2705}"
    case .tookALongTime:
        color = .yellow
        glyph = "\u{26A0}"
    case .failed:
        color = .red
        glyph = "\u{274C}"
    }
    log(" \(glyph) \(branch.name) --> \(branch.target)", color: color)
}
log("")

let printStaleBranchWarning: () -> () = {
    let slowMergeCount = mergeResults.values.filter { $0 == .tookALongTime }.count
    if slowMergeCount > 0 {
        log("At least one merge took longer than \(mergeTimeWarningUpperBound) seconds; consider updating these branches with the latest from their respective parent branches.", color: .yellow)
    }
}

if let firstBranchWithConflicts = firstBranchWithConflicts {
    let conflictCount = conflicts.count
    log("Found \(conflictCount) conflict\(conflictCount == 1 ? "" : "s").", color: .red)
    printStaleBranchWarning()
    log("")
    log("Checked out the first conflict for you to fix: \(LogColor.red.terminalString)\(firstBranchWithConflicts.name)\(LogColor.blue.terminalString) --> \(firstBranchWithConflicts.target)")
} else {
    log("No conflicts detected.")
    printStaleBranchWarning()
    log("")
    log("Returned to \(defaultBranch) (your default branch).")
}
