/*
Copyright 2021-Present Couchbase, Inc.

Use of this software is governed by the Business Source License included in
the file licenses/BSL-Couchbase.txt.  As of the Change Date specified in that
file, in accordance with the Business Source License, use of this software will
be governed by the Apache License, Version 2.0, included in the file
licenses/APL2.txt.
*/

import {ChangeDetectionStrategy, Component} from '../web_modules/@angular/core.js';
import {MnLifeCycleHooksToStream} from './mn.core.js';
import {NgbActiveModal} from '../web_modules/@ng-bootstrap/ng-bootstrap.js';
import {ClipboardService} from '../web_modules/ngx-clipboard.js';
import {MnAlertsService} from './ajs.upgraded.providers.js';
import {MnLogsCollectInfoService} from './mn.logs.collectInfo.service.js';
import {takeUntil, filter, map} from '../web_modules/rxjs/operators.js';

export { MnClusterSummaryDialogComponent };

class MnClusterSummaryDialogComponent extends MnLifeCycleHooksToStream {

  static get annotations() { return [
    new Component({
      selector: "mn-cluster-summary-dialog",
      templateUrl: "/ui/app/mn.cluster.summary.dialog.html",
      providers: [
        ClipboardService
      ],
      changeDetection: ChangeDetectionStrategy.OnPush
    })
  ]}

  static get parameters() { return [
    NgbActiveModal,
    ClipboardService,
    MnAlertsService,
    MnLogsCollectInfoService
  ]}

  constructor(activeModal, clipboardService, mnAlertsService, mnLogsCollectInfoService) {
    super();

    this.activeModal = activeModal;
    this.mnAlertsService = mnAlertsService;

    this.clusterInfo = mnLogsCollectInfoService.stream.clusterInfo
      .pipe(map(v => JSON.stringify(v, null, 2)));

    clipboardService.copyResponse$
      .pipe(filter(response => response.isSuccess),
            takeUntil(this.mnOnDestroy))
      .subscribe(this.handleSuccessMessage.bind(this));

    clipboardService.copyResponse$
      .pipe(filter(response => !response.isSuccess),
            takeUntil(this.mnOnDestroy))
      .subscribe(this.handleErrorMessage.bind(this));
  }

  handleSuccessMessage() {
    this.activeModal.close();
    this.mnAlertsService.formatAndSetAlerts('Text copied successfully!',
                                            'success',
                                            2500);
  }

  handleErrorMessage() {
    this.activeModal.close();
    this.mnAlertsService.formatAndSetAlerts('Unable to copy text!',
                                            'error',
                                            2500);
  }
}
