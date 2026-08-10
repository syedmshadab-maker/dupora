import 'package:path/path.dart' as p;

import '../../deletion/protected_locations.dart';
import '../../scanner/domain/scanned_file.dart';
import 'duplicate_group.dart';

enum SmartSelectionStrategy { keepOldest, keepNewest, keepShortestPath, keepFirst }

/// Result of applying a [SmartSelectionStrategy] to a [DuplicateGroup]:
/// exactly one file to keep, and the rest marked for deletion. The kept
/// file is never included in [selectedForDeletion], and a protected file is
/// never selected for deletion even if the strategy would otherwise have
/// chosen it as a duplicate.
class SelectionResult {
  const SelectionResult({required this.keep, required this.selectedForDeletion});

  final ScannedFile keep;
  final List<ScannedFile> selectedForDeletion;
}

/// Chooses which copy to keep and marks the rest for deletion.
///
/// "Keep system drive" is intentionally not a selectable strategy on its
/// own: protection is enforced universally via [ProtectedLocations] so a
/// protected copy is *never* selected for deletion regardless of which
/// strategy picked the nominal "keep" file - see [apply].
SelectionResult applySmartSelection(
  DuplicateGroup group,
  SmartSelectionStrategy strategy,
  ProtectedLocations protectedLocations,
) {
  final files = group.files;
  late final ScannedFile keep;
  switch (strategy) {
    case SmartSelectionStrategy.keepOldest:
      keep = files.reduce((a, b) => a.modifiedAt.isBefore(b.modifiedAt) ? a : b);
    case SmartSelectionStrategy.keepNewest:
      keep = files.reduce((a, b) => a.modifiedAt.isAfter(b.modifiedAt) ? a : b);
    case SmartSelectionStrategy.keepShortestPath:
      keep = files.reduce((a, b) => a.path.length <= b.path.length ? a : b);
    case SmartSelectionStrategy.keepFirst:
      keep = files.first;
  }

  final selected = <ScannedFile>[
    for (final f in files)
      if (f != keep && !protectedLocations.isProtected(f.path)) f,
  ];

  return SelectionResult(keep: keep, selectedForDeletion: selected);
}

/// Selects every duplicate in the group (everything but [keep]), still
/// honoring protected locations. Useful for a "select all duplicates"
/// bulk action across many groups where [keep] was already chosen per-group
/// (e.g. by a prior smart-selection pass).
List<ScannedFile> selectAllDuplicates(
  DuplicateGroup group,
  ScannedFile keep,
  ProtectedLocations protectedLocations,
) {
  return [
    for (final f in group.files)
      if (f != keep && !protectedLocations.isProtected(f.path)) f,
  ];
}

/// True if [a] is on what looks like the OS-installation drive/root - used
/// only as a tiebreaker hint in the UI (e.g. sort keep-candidates), never as
/// the sole basis for protection, which is [ProtectedLocations]'s job.
bool looksLikeSystemDrivePath(String path) {
  final root = p.rootPrefix(path);
  return root.toUpperCase().startsWith('C:');
}
