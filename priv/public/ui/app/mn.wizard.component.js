/*
Copyright 2020-Present Couchbase, Inc.

Use of this software is governed by the Business Source License included in
the file licenses/BSL-Couchbase.txt.  As of the Change Date specified in that
file, in accordance with the Business Source License, use of this software will
be governed by the Apache License, Version 2.0, included in the file
licenses/APL2.txt.
*/

import {MnWizardService} from './mn.wizard.service.js';
import {MnLifeCycleHooksToStream} from './mn.core.js';
import {MnPoolsService} from './mn.pools.service.js';
import {MnAdminService} from "./mn.admin.service.js";
import {first} from '../web_modules/rxjs/operators.js';
import {FormGroup, FormControl} from '../web_modules/@angular/forms.js';
import {Component, ChangeDetectionStrategy} from '../web_modules/@angular/core.js';

export {MnWizardComponent};

class MnWizardComponent extends MnLifeCycleHooksToStream {

  static get annotations() { return [
    new Component({
      templateUrl: 'app/mn.wizard.html',
      changeDetection: ChangeDetectionStrategy.OnPush
    })
  ]}

  static get parameters() { return [
    MnWizardService,
    MnPoolsService,
    MnAdminService
  ]}

  constructor(mnWizardService, mnPoolsService, mnAdminService) {
    super();
    var newClusterConfig = mnWizardService.wizardForm.newClusterConfig;
    var joinCluster = mnWizardService.wizardForm.joinCluster;
    //MnExceptionHandlerService.stream.appException.subscribe(MnExceptionHandlerService.send);

    mnAdminService.stream.implementationVersion
      .pipe(first())
      .subscribe(function (implementationVersion) {
        mnWizardService.initialValues.implementationVersion = implementationVersion;
      });

    mnWizardService.stream.getSelfConfig
      .pipe(first())
      .subscribe(v => mnWizardService.setSelfConfig(v));

    function servicesToGroup(services, value) {
      return new FormGroup(services.reduce(function (acc, name) {
        acc[name] = new FormControl(value);
        return acc;
      }, {}));
    }

    mnPoolsService.stream.mnServices.pipe(first())
      .subscribe(function (services) {
        newClusterConfig.get("services").addControl("flag", servicesToGroup(services, true));
        joinCluster.get("services").addControl("flag", servicesToGroup(services, true));
        newClusterConfig.get("services.flag.kv").disable({onlySelf: true});
      });

    mnPoolsService.stream.quotaServices.pipe(first())
      .subscribe(function (services) {
        newClusterConfig.get("services").addControl("field", servicesToGroup(services, null));
      });

    mnPoolsService.stream.isEnterprise.pipe(first())
      .subscribe(function (isEnterprise) {
        var storageMode = isEnterprise ? "plasma" : "forestdb";
        newClusterConfig.get("storageMode").setValue(storageMode);

        if (!isEnterprise) {
          joinCluster.get("clusterStorage.storage.cbas_path").disable({onlySelf: true});
          newClusterConfig.get("clusterStorage.storage.cbas_path").disable({onlySelf: true});
        }

        mnWizardService.initialValues.storageMode = storageMode;
      });

    mnWizardService.stream.initHddStorage.pipe(first())
      .subscribe(function (initHdd) {
        newClusterConfig.get("clusterStorage.storage").patchValue(initHdd);
        joinCluster.get("clusterStorage.storage").patchValue(initHdd);

        mnWizardService.initialValues.clusterStorage = initHdd;
      });
  }
}
