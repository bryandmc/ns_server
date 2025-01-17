/*
Copyright 2020-Present Couchbase, Inc.

Use of this software is governed by the Business Source License included in
the file licenses/BSL-Couchbase.txt.  As of the Change Date specified in that
file, in accordance with the Business Source License, use of this software will
be governed by the Apache License, Version 2.0, included in the file
licenses/APL2.txt.
*/
import { singletonGuard } from './mn.core.js';
import { NgModule } from '../web_modules/@angular/core.js';
import { Injectable } from '../web_modules/@angular/core.js';
import { HttpClient } from '../web_modules/@angular/common/http.js';
import { BehaviorSubject } from '../web_modules/rxjs.js';
import { switchMap, shareReplay, pluck,
         distinctUntilChanged, map } from '../web_modules/rxjs/operators.js';
import { servicesEnterprise } from '/ui/app/constants/constants.js';
import { servicesCE } from '/ui/app/constants/constants.js';

export { MnPoolsService, MnPoolsServiceModule };

let launchID =  (new Date()).valueOf() + '-' + ((Math.random() * 65536) >> 0);

class MnPoolsServiceModule {
  static get annotations() { return [
    new NgModule({
      imports: [],
      providers: [
        MnPoolsService
      ]
    })
  ]}
}

class MnPoolsService {
  static get annotations() { return [
    new Injectable()
  ]}

  static get parameters() { return [
    HttpClient
  ]}

  constructor(http) {
    singletonGuard(MnPoolsService);

    this.http = http;
    this.stream = {};

    this.stream.getSuccess =
      (new BehaviorSubject()).pipe(switchMap(this.get.bind(this)),
                                   shareReplay({refCount: true, bufferSize: 1}));

    this.stream.isEnterprise =
      this.stream.getSuccess.pipe(pluck("isEnterprise"), distinctUntilChanged());

    this.stream.isStrippingPort =
      this.stream.getSuccess.pipe(pluck("isStrippingPort"), distinctUntilChanged());

    this.stream.mnServices =
      this.stream.isEnterprise
      .pipe(map(function (isEnterprise) {
        return isEnterprise ? servicesEnterprise : servicesCE;
      }), shareReplay({refCount: true, bufferSize: 1}));

    this.stream.quotaServices =
      this.stream.isEnterprise
      .pipe(map(function (isEnterprise) {
        return isEnterprise ?
          ["kv", "index", "fts", "cbas", "eventing"] :
          ["kv", "index", "fts"];
      }), shareReplay({refCount: true, bufferSize: 1}));
  }

  getServiceVisibleName(service) {
    switch (service) {
    case "kv": return "Data";
    case "index": return "Index";
    case "fts": return "Search";
    case "n1ql": return "Query";
    case "eventing": return "Eventing";
    case "cbas": return "Analytics";
    case "backup": return "Backup";
    }
  }

  getServiceQuotaName(service) {
    switch (service) {
    case "kv": return "memoryQuota";
    default: return service + "MemoryQuota";
    }
  }

  pluckMemoryQuotas(source) {
    return source[1].reduce((acc, service) => {
      acc[service] = source[0][this.getServiceQuotaName(service)];
      return acc;
    }, {});
  }

  get() {
    return this.http.get('/pools').pipe(
      map(function (pools) {
        pools.isInitialized = !!pools.pools.length;
        pools.launchID = pools.uuid + '-' + launchID;
        return pools;
      })
    );
  }
}
