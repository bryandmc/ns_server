/*
  Copyright 2021-Present Couchbase, Inc.

  Use of this software is governed by the Business Source License included in
  the file licenses/BSL-Couchbase.txt.  As of the Change Date specified in that
  file, in accordance with the Business Source License, use of this software will
  be governed by the Apache License, Version 2.0, included in the file
  licenses/APL2.txt.
*/

import { ChangeDetectionStrategy, Component } from '../web_modules/@angular/core.js';
import { MnHelperService } from './mn.helper.service.js';

export { MnTextExpanderComponent };

class MnTextExpanderComponent {
  static get annotations() { return [
    new Component({
      selector: "mn-text-expander",
      templateUrl: "app/mn.text.expander.html",
      inputs: [
        "text",
        "limit"
      ],
      changeDetection: ChangeDetectionStrategy.OnPush
    })
  ]}

  static get parameters() { return [
    MnHelperService
  ]}

  constructor(mnHelperService) {
    this.toggler = mnHelperService.createToggle();
    this.Infinity = Infinity;
  }

  ngOnInit() {
    this.isOverLimit = this.text && (this.text.length > parseInt(this.limit, 10));
  }
}
