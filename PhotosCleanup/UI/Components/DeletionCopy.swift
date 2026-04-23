//
//  DeletionCopy.swift
//  PhotosCleanup
//
//  Shared copy for deletion confirmations: Recently Deleted + iCloud note per PRD.
//

import Foundation

enum DeletionCopy {
    /// Message for confirmation dialogs before moving items to Recently Deleted.
    static let confirmationMessage = "Selected items will be moved to Recently Deleted and can be recovered for about 30 days. If you use iCloud Photos, deletions will sync and remove them from all your devices."
    /// Shorter variant when the next screen already explains undo.
    static let confirmationMessageWithUndoNext = "They will go to Recently Deleted. You can undo from the next screen. If you use iCloud Photos, deletions will sync to all devices."
    /// For mode-specific copy that already mentions "low quality" etc.
    static func confirmationMessageModeSpecific(prefix: String) -> String {
        "\(prefix) They will go to Recently Deleted (about 30 days). If you use iCloud Photos, deletions will sync to all devices."
    }
}
