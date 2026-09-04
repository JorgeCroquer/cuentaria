/// Runs the shared [CloudFolder] contract (packages/backup) against the
/// real Google Drive API (issue #225 AC "el contract test de F3.1 corre
/// verde contra Drive real"). Off-sandbox: external — see the "Correr el
/// contract test contra Drive real" section of
/// lib/features/cloud_copy/README.md for how to get a token and run this
/// by hand. Tagged `google_drive`, skipped by default (dart_test.yaml); run
/// with `--tags google_drive --run-skipped`.
library;

import 'package:backup/testing/cloud_folder_contract.dart';
import 'package:cuentaria_app/features/cloud_copy/infrastructure/google_drive_cloud_folder.dart';

import 'cloud_copy_test_support.dart';

const _accessToken = String.fromEnvironment('GOOGLE_DRIVE_TEST_TOKEN');

void main() {
  cloudFolderContractTests(
    () => GoogleDriveCloudFolder(
      FakeGoogleDriveSession(_accessToken.isEmpty ? null : _accessToken),
    ),
    tags: ['google_drive'],
  );
}
