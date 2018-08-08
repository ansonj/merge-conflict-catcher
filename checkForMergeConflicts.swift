#! /usr/bin/env swift

import Foundation

// MARK: - Customize the definitions below

let remote = "origin"
let defaultBranch = "master"

struct Branch: Hashable {
    let name: String
    let target: String
    init(name: String, target: String = defaultBranch) {
        self.name = name
        self.target = target
    }
}

let branches: [Branch] = [
    Branch(name: "<#my-fancy-branch#>")
]

// MARK: - End of customizable section

enum LogColor: Int {
    // https://github.com/mtynior/ColorizeSwift/blob/master/Source/ColorizeSwift.swift
    case black = 0
    case red = 31
    case green = 32
    case blue = 34
    
    var terminalString: String {
        return "\u{001B}[\(self.rawValue)m"
    }
}

func log(_ message: String, color: LogColor = .blue) {
    print("\(color.terminalString)==> \(message)\(LogColor.black.terminalString)")
}

func run(gitCommand args: String) -> Int32 {
    // https://stackoverflow.com/a/26973384
    let command = "git " + args
    log(command)
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = command.split(separator: " ").map { String($0) }
    task.launch()
    task.waitUntilExit()
    return task.terminationStatus
}

func run(gitCommand args: String, andFailWithDescriptionIfNeeded description: String) {
    let exitStatus = run(gitCommand: args)
    guard exitStatus == 0 else {
        log("\(description) failed with exit status \(exitStatus)")
        exit(exitStatus)
    }
}

var mergeSucceeded = [Branch : Bool]()

run(gitCommand: "fetch --jobs=5 --recurse-submodules", andFailWithDescriptionIfNeeded: "Fetch")

var testsComplete: Int = 0
for branch in branches {
    run(gitCommand: "checkout --detach \(branch.name)", andFailWithDescriptionIfNeeded: "Checkout \(branch.name)")
    let mergeExitStatus = run(gitCommand: "merge --no-edit origin/\(branch.target)")
    if mergeExitStatus != 0 {
        log("Merge conflict detected: \(branch.name) --> \(branch.target)", color: .red)
        mergeSucceeded[branch] = false
        run(gitCommand: "merge --abort", andFailWithDescriptionIfNeeded: "Merge abort")
    } else {
        mergeSucceeded[branch] = true
    }
    testsComplete += 1
    log("Tested \(testsComplete) of \(branches.count) merges...")
}

let firstBranchWithConflicts: Branch? = branches.filter { mergeSucceeded[$0] == false }.first
let branchToResetTo = firstBranchWithConflicts?.name ?? defaultBranch
run(gitCommand: "checkout \(branchToResetTo)", andFailWithDescriptionIfNeeded: "Checkout \(branchToResetTo)")
run(gitCommand: "submodule update --init --recursive", andFailWithDescriptionIfNeeded: "Submodule update")

log("")
log("Results:")
for branch in branches {
    let color: LogColor
    let glyph: String
    if mergeSucceeded[branch, default: false] {
        color = .green
        glyph = "\u{2705}"
    } else {
        color = .red
        glyph = "\u{274C}"
    }
    log(" \(glyph) \(branch.name) --> \(branch.target)", color: color)
}
log("")

if let firstBranchWithConflicts = firstBranchWithConflicts {
    let conflictCount = branches.filter { mergeSucceeded[$0] == false }.count
    log("Found \(conflictCount) conflict\(conflictCount == 1 ? "" : "s").", color: .red)
    log("")
    log("Checked out the first conflict for you to fix: \(LogColor.red.terminalString)\(firstBranchWithConflicts.name)\(LogColor.blue.terminalString) --> \(firstBranchWithConflicts.target)")
} else {
    log("No conflicts detected.")
    log("")
    log("Returned to \(defaultBranch) (your default branch).")
}
