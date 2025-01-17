/*
Copyright 2020-Present Couchbase, Inc.

Use of this software is governed by the Business Source License included in
the file licenses/BSL-Couchbase.txt.  As of the Change Date specified in that
file, in accordance with the Business Source License, use of this software will
be governed by the Apache License, Version 2.0, included in the file
licenses/APL2.txt.
*/

export default mnBucketsDeleteDialogController;

function mnBucketsDeleteDialogController($uibModalInstance, bucket, mnPromiseHelper, mnBucketsDetailsService) {
  var vm = this;
  vm.doDelete = doDelete;
  vm.bucketName = bucket.name;

  function doDelete() {
    var promise = mnBucketsDetailsService.deleteBucket(bucket);
    mnPromiseHelper(vm, promise, $uibModalInstance)
      .showGlobalSpinner()
      .catchGlobalErrors()
      .closeFinally()
      .showGlobalSuccess("Bucket deleted successfully!");
  }
}
