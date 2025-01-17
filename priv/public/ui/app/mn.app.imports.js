/*
Copyright 2020-Present Couchbase, Inc.

Use of this software is governed by the Business Source License included in
the file licenses/BSL-Couchbase.txt.  As of the Change Date specified in that
file, in accordance with the Business Source License, use of this software will
be governed by the Apache License, Version 2.0, included in the file
licenses/APL2.txt.
*/

import {CommonModule} from '../web_modules/@angular/common.js';
import {BrowserModule} from '../web_modules/@angular/platform-browser.js';
import {HttpClientModule} from '../web_modules/@angular/common/http.js';
import {UIRouterModule, loadNgModule} from '../web_modules/@uirouter/angular.js';
import {Rejection} from '../web_modules/@uirouter/core.js';
import {MnPipesModule} from './mn.pipes.module.js';
import {UpgradeModule} from '../web_modules/@angular/upgrade/static.js';
import {MnSharedModule} from './mn.shared.module.js';
import {MnElementCraneModule} from './mn.element.crane.js';
import {UIRouterUpgradeModule} from '../web_modules/@uirouter/angular-hybrid.js';
import * as pluggableUIsModules from '/ui/pluggable-uis.js';
import {MnPoolsServiceModule} from './mn.pools.service.js';
import {MnAdminServiceModule} from './mn.admin.service.js';
import {MnCollectionsServiceModule} from './mn.collections.service.js';
import {MnKeyspaceSelectorServiceModule} from "./mn.keyspace.selector.service.js";
import {MnKeyspaceSelectorModule} from './mn.keyspace.selector.module.js';
import {MnHelper} from './ajs.upgraded.providers.js';

let wizardState = {
  name: 'app.wizard.**',
  lazyLoad: mnLoadNgModule('./mn.wizard.module.js', 'MnWizardModule')
};

let collectionsState = {
  name: 'app.admin.collections.**',
  url: '/collections',
  lazyLoad: mnLoadNgModule('./mn.collections.module.js', 'MnCollectionsModule')
};

let XDCRState = {
  name: 'app.admin.replications.**',
  url: '/replications',
  lazyLoad: mnLoadNgModule('./mn.xdcr.module.js', "MnXDCRModule")
};

let otherSecuritySettingsState = {
  name: 'app.admin.security.other.**',
  url: '/other',
  lazyLoad: mnLoadNgModule('./mn.security.other.module.js', 'MnSecurityOtherModule')
};

let auditState = {
  name: 'app.admin.security.audit.**',
  url: '/audit',
  lazyLoad: mnLoadNgModule('./mn.security.audit.module.js', 'MnSecurityAuditModule')
};

let overviewState = {
  name: 'app.admin.overview.**',
  url: '/overview',
  lazyLoad: mnLazyload('./mn_admin/mn_overview_controller.js', 'mnOverview')
};

let serversState = {
  name: 'app.admin.servers.**',
  url: '/servers',
  lazyLoad: mnLazyload('./mn_admin/mn_servers_controller.js', 'mnServers')
};

let logsState = {
  name: 'app.admin.logs.**',
  url: '/logs',
  lazyLoad: mnLazyload('./mn_admin/mn_logs_controller.js', "mnLogs")
};

let logsListState = {
  name: "app.admin.logs.list.**",
  url: "",
  lazyLoad: mnLoadNgModule('./mn.logs.list.module.js', "MnLogsListModule")
};

let logsCollectInfo = {
  name: "app.admin.logs.collectInfo.**",
  url: "/collectInfo",
  lazyLoad: mnLoadNgModule('./mn.logs.collectInfo.module.js', "MnLogsCollectInfoModule")
}

let groupsState = {
  name: 'app.admin.groups.**',
  url: '/groups',
  lazyLoad: mnLazyload('./mn_admin/mn_groups_controller.js', 'mnGroups')
};

let bucketsState = {
  name: 'app.admin.buckets.**',
  url: '/buckets',
  lazyLoad: mnLazyload('./mn_admin/mn_buckets_controller.js', 'mnBuckets')
};

let authState = {
  name: "app.auth.**",
  lazyLoad: mnLoadNgModule('./mn.auth.module.js', 'MnAuthModule')
};

let gsiState = {
  name: "app.admin.gsi.**",
  url: "/index",
  lazyLoad: mnLazyload('./mn_admin/mn_gsi_controller.js', 'mnGsi')
};

let viewsState = {
  name: "app.admin.views.**",
  url: "/views",
  lazyLoad: mnLazyload('./mn_admin/mn_views_controller.js', "mnViews")
};

let settingsState = {
  name: "app.admin.settings.**",
  url: "/settings",
  lazyLoad: mnLazyload('./mn_admin/mn_settings_config.js', "mnSettings")
};

let sampleBucketState = {
  name: 'app.admin.settings.sampleBuckets.**',
  url: '/sampleBuckets',
  lazyLoad: mnLoadNgModule('./mn.settings.sample.buckets.module.js', 'MnSettingsSampleBucketsModule')
};

let alertsState = {
  name: "app.admin.settings.alerts.**",
  url: "/alerts",
  lazyLoad: mnLoadNgModule('./mn.settings.alerts.module.js', "MnSettingsAlertsModule")
};

let autoCompactionState = {
  name: 'app.admin.settings.autoCompaction.**',
  url: '/autoCompaction',
  lazyLoad: mnLoadNgModule('./mn.settings.auto.compaction.module.js', 'MnSettingsAutoCompactionModule')
}

let securityState = {
  name: "app.admin.security.**",
  url: "/security",
  lazyLoad: mnLazyload('./mn_admin/mn_security_config.js', "mnSecurity")
};

function rejectTransition() {
  return Promise.reject(Rejection.superseded("Lazy loading has been suppressed by another transition"));
}

function ocLazyLoad($transition$, module, initialHref) {
  return $transition$
    .injector()
    .get('$ocLazyLoad')
    .load({name: module})
    .then(result => {
      let postLoadHref = window.location.href;
      return initialHref === postLoadHref ? result : rejectTransition();
    });
}

function mnLazyload(url, module) {
  return ($transition$) => {
    let initialHref = window.location.href;

    let mnHelper = $transition$.injector().get('mnHelper');
    mnHelper.mainSpinnerCounter.increase();

    return import(url).then(() => {
      let postImportHref = window.location.href;

      return initialHref === postImportHref ?
        ocLazyLoad($transition$, module, initialHref) :
        rejectTransition();

    }).finally(() => mnHelper.mainSpinnerCounter.decrease());
  };
}

function mnLoadNgModule(url, module) {
  return (transition, stateObject) => {
    let initialHref = window.location.href;

    let mnHelper = transition.injector().get(MnHelper);
    mnHelper.mainSpinnerCounter.increase();

    let lazyLoadFn = loadNgModule(() => import(url).then(result => {
      let postImportHref = window.location.href;
      return initialHref === postImportHref ? result[module] : rejectTransition();
    }));

    return lazyLoadFn(transition, stateObject).then(result => {
      let postLoadHref = window.location.href;
      return initialHref === postLoadHref ? result : rejectTransition();

    }).finally(() => mnHelper.mainSpinnerCounter.decrease());
  };
}

let mnAppImports = [
  ...Object.values(pluggableUIsModules),
  UpgradeModule,
  UIRouterModule,
  MnPipesModule,
  BrowserModule,
  CommonModule,
  HttpClientModule,
  MnSharedModule,
  MnCollectionsServiceModule,
  MnAdminServiceModule,
  MnPoolsServiceModule,
  MnKeyspaceSelectorServiceModule,
  MnElementCraneModule.forRoot(),
  UIRouterUpgradeModule.forRoot({
    states: [
      authState,
      wizardState,
      overviewState,
      serversState,
      bucketsState,
      logsState,
      logsListState,
      logsCollectInfo,
      alertsState,
      groupsState,
      gsiState,
      viewsState,
      settingsState,
      sampleBucketState,
      autoCompactionState,
      securityState,
      collectionsState,
      XDCRState,
      otherSecuritySettingsState,
      auditState
    ]
  }),

  //downgradedModules
  MnKeyspaceSelectorModule
];

export {mnAppImports, mnLoadNgModule, mnLazyload};
