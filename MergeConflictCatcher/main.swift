#!/usr/bin/env swift

import Foundation

// MARK: - Types

var defaultBranchName: String

struct Branch: Hashable {
    let name: String
    let target: String
    init(name: String, target: String = defaultBranchName) {
        self.name = name
        self.target = target
    }
}

enum DesiredFinalCheckoutState {
    case firstConflict
    case defaultBranch
    case nothing
}

// MARK: - Customize the definitions below

let remote = "origin"
defaultBranchName = "master"
let desiredFinalState = DesiredFinalCheckoutState.firstConflict
let mergeTimeWarningUpperBound: TimeInterval = 1.0

let branches: [Branch] = [
    Branch(name: "<#my-fancy-branch#>"),
    Branch(name: "<#my-urgent-hotfix#>", target: "<#release-branch#>")
]

// MARK: - End of customizable section

extension Branch {
    var remoteName: String {
        return remote + "/" + name
    }
    var remoteTarget: String {
        return remote + "/" + target
    }
}

enum ActualFinalCheckoutState {
    case firstConflict(branch: Branch)
    case defaultBranch
    case nothing
}

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
        log("\(description) failed with exit status \(exitStatus)", color: .red)
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
    run(gitCommand: "checkout --detach \(branch.remoteTarget)", andFailWithDescriptionIfNeeded: "Checkout detached HEAD at \(branch.remoteTarget)")
    let mergeCompletionInfo = run(gitCommand: "merge --no-edit \(branch.remoteName)")
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

let finalState: ActualFinalCheckoutState
// Figure out where we're going to end up
switch (desiredFinalState, conflicts.first) {
case (.firstConflict, .some(let firstBranchWithConflicts)):
    finalState = .firstConflict(branch: firstBranchWithConflicts)
case (.firstConflict, .none):
    finalState = .defaultBranch
case (.defaultBranch, _):
    finalState = .defaultBranch
case (.nothing, _):
    finalState = .nothing
}
// Checkout if needed
func reset(toBranchName branchName: String) {
    run(gitCommand: "checkout \(branchName)", andFailWithDescriptionIfNeeded: "Checkout \(branchName)")
    run(gitCommand: "submodule update --init --recursive", andFailWithDescriptionIfNeeded: "Submodule update")
}
switch finalState {
case .firstConflict(let branch):
    reset(toBranchName: branch.name)
case .defaultBranch:
    reset(toBranchName: defaultBranchName)
case .nothing:
    break
}

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

let printStaleBranchWarningIfNeeded: () -> () = {
    let slowMergeCount = mergeResults.values.filter { $0 == .tookALongTime }.count
    if slowMergeCount > 0 {
        log("At least one merge took longer than \(mergeTimeWarningUpperBound) seconds;", color: .yellow)
        log("consider updating these branches with the latest from their respective parent branches.", color: .yellow)
    }
}

if conflicts.count > 0 {
    log("Found \(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s").", color: .red)
} else {
    log("No conflicts detected.")
}
printStaleBranchWarningIfNeeded()
log("")
switch finalState {
case .firstConflict(let branch):
    log("Checked out the first conflict for you to fix: \(LogColor.red.terminalString)\(branch.name)\(LogColor.blue.terminalString) --> \(branch.target)")
case .defaultBranch:
    log("Returned to \(defaultBranchName) (your default branch).")
case .nothing:
    log("Skipping final checkout.")
}
