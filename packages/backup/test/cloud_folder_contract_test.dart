import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:backup/testing/cloud_folder_contract.dart';
import 'package:test/test.dart';

void main() {
  group('CloudFolder contract [InMemoryCloudFolder]', () {
    cloudFolderContractTests(() => InMemoryCloudFolder());
  });
}
