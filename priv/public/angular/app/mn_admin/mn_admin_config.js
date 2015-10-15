angular.module('mnAdmin', [
  'mnAlertsService',
  'mnTasksDetails',
  'mnAuthService',
  'mnHelper',
  'mnPromiseHelper',
  'mnBuckets',
  'mnAnalytics',
  'mnLogs',
  'mnOverview',
  'mnIndexes',
  'mnServers',
  'mnGroups',
  'mnDocuments',
  'mnSettingsNotifications',
  'mnSettingsLdap',
  'mnSettingsSampleBuckets',
  'mnSettingsCluster',
  'mnSettingsAutoFailover',
  'mnSettingsAutoCompaction',
  'mnSettingsAudit',
  'mnSettingsCluster',
  'mnSettingsAlerts',
  'mnSettingsNotificationsService',
  'mnAccountManagement',
  'mnViews',
  'mnXDCR',
  'mnPoll',
  'mnLaunchpad'
]).config(function ($stateProvider, $urlRouterProvider, $urlMatcherFactoryProvider) {

  function valToString(val) {
    return val != null ? val.toString() : val;
  }
  $urlMatcherFactoryProvider.type("string", {
    encode: valToString,
    decode: valToString,
    is: function (val) {
      return (/[^/]*/).test(val);
    }
  });

  $stateProvider
    .state('app.admin', {
      abstract: true,
      templateUrl: 'mn_admin/mn_admin.html',
      controller: 'mnAdminController as mnAdminController',
      resolve: {
        poolDefault: function (mnPoolDefault) {
          return mnPoolDefault.get();
        }
      }
    })
    .state('app.admin.overview', {
      url: '/overview',
      controller: 'mnOverviewController',
      templateUrl: 'mn_admin/mn_overview/mn_overview.html'
    })
    .state('app.admin.documents', {
      abstract: true,
      templateUrl: 'mn_admin/mn_documents/mn_documents.html',
      data: {
        required: {
          admin: true
        }
      },
      params: {
        pageLimit: {
          value: 5
        },
        pageNumber: {
          value: 0
        },
        documentsFilter: null
      },
      controller: "mnDocumentsController as mnDocumentsController",
      url: "/documents?documentsBucket&{pageLimit:int}&{pageNumber:int}&documentsFilter"
    })
    .state('app.admin.documents.list', {
      url: "",
      controller: 'mnDocumentsListController as mnDocumentsListController',
      templateUrl: 'mn_admin/mn_documents/list/mn_documents_list.html'
    })
    .state('app.admin.documents.editing', {
      url: '/:documentId',
      controller: 'mnDocumentsEditingController as mnDocumentsEditingController',
      templateUrl: 'mn_admin/mn_documents/editing/mn_documents_editing.html'
    })
    .state('app.admin.analytics', {
      abstract: true,
      url: '/analytics?statsHostname&analyticsBucket&zoom&specificStat',
      params: {
        zoom: {
          value: 'minute'
        }
      },
      controller: 'mnAnalyticsController',
      templateUrl: 'mn_admin/mn_analytics/mn_analytics.html'
    })
    .state('app.admin.analytics.list', {
      abstract: true,
      url: '?openedStatsBlock',
      params: {
        openedStatsBlock: {
          array: true
        }
      },
      controller: 'mnAnalyticsListController',
      templateUrl: 'mn_admin/mn_analytics/mn_analytics_list.html'
    })
    .state('app.admin.analytics.list.graph', {
      url: '/:graph',
      params: {
        graph: {
          value: 'ops'
        }
      },
      controller: 'mnAnalyticsListGraphController',
      templateUrl: 'mn_admin/mn_analytics/mn_analytics_list_graph.html'
    })
    .state('app.admin.views', {
      abstract: true,
      url: '/views?viewsBucket',
      params: {
        type: {
          value: 'development'
        }
      },
      templateUrl: 'mn_admin/mn_views/mn_views.html',
      controller: 'mnViewsController as mnViewsController'
    })
    .state('app.admin.views.list', {
      url: "?type",
      controller: 'mnViewsListController as mnViewsListController',
      templateUrl: 'mn_admin/mn_views/list/mn_views_list.html'
    })
    .state('app.admin.views.editing', {
      abstract: true,
      url: '/:documentId/:viewId?{isSpatial:bool}&sampleDocumentId',
      controller: 'mnViewsEditingController as mnViewsEditingController',
      templateUrl: 'mn_admin/mn_views/editing/mn_views_editing.html',
      data: {
        required: {
          admin: true
        }
      }
    })
    .state('app.admin.views.editing.result', {
      url: '?subset&{pageNumber:int}&viewsParams',
      params: {
        full_set: {
          value: null
        },
        pageNumber: {
          value: 0
        }
      },
      controller: 'mnViewsEditingResultController as mnViewsEditingResultController',
      templateUrl: 'mn_admin/mn_views/editing/mn_views_editing_result.html'
    })
    .state('app.admin.buckets', {
      url: '/buckets?openedBucket',
      params: {
        openedBucket: {
          array: true
        }
      },
      views: {
        "": {
          controller: 'mnBucketsController',
          templateUrl: 'mn_admin/mn_buckets/mn_buckets.html'
        },
        "details@app.admin.buckets": {
          templateUrl: 'mn_admin/mn_buckets/details/mn_buckets_details.html',
          controller: 'mnBucketsDetailsController'
        }
      }
    })
    .state('app.admin.indexes', {
      url: "/index?openedIndex",
      params: {
        openedIndex: {
          array: true
        }
      },
      controller: "mnIndexesController",
      templateUrl: "mn_admin/mn_indexes/mn_indexes.html"
    })
    .state('app.admin.servers', {
      url: '/servers/:list?openedServers',
      params: {
        list: {
          value: 'active'
        },
        openedServers: {
          array: true
        }
      },
      views: {
        "" : {
          controller: 'mnServersController',
          templateUrl: 'mn_admin/mn_servers/mn_servers.html'
        },
        "details@app.admin.servers": {
          templateUrl: 'mn_admin/mn_servers/details/mn_servers_list_item_details.html',
          controller: 'mnServersListItemDetailsController'
        }
      }
    })
    .state('app.admin.groups', {
      url: '/groups',
      templateUrl: 'mn_admin/mn_groups/mn_groups.html',
      controller: 'mnGroupsController',
      controllerAs: 'mnGroupsController',
      data: {
        required: {
          admin: true
        }
      }
    })
    .state('app.admin.replications', {
      url: '/replications',
      templateUrl: 'mn_admin/mn_xdcr/mn_xdcr.html',
      controller: 'mnXDCRController'
    })
    .state('app.admin.logs', {
      url: '/logs',
      abstract: true,
      templateUrl: 'mn_admin/mn_logs/mn_logs.html',
      controller: 'mnLogsController as mnLogsController'
    })
    .state('app.admin.logs.list', {
      url: '',
      controller: 'mnLogsListController',
      templateUrl: 'mn_admin/mn_logs/list/mn_logs_list.html'
    })
    .state('app.admin.logs.collectInfo', {
      url: '/collectInfo',
      abstract: true,
      controller: 'mnLogsCollectInfoController',
      templateUrl: 'mn_admin/mn_logs/collect_info/mn_logs_collect_info.html',
      data: {
        required: {
          admin: true
        }
      }
    })
    .state('app.admin.logs.collectInfo.result', {
      url: '/result',
      templateUrl: 'mn_admin/mn_logs/collect_info/mn_logs_collect_info_result.html'
    })
    .state('app.admin.logs.collectInfo.form', {
      url: '/form',
      templateUrl: 'mn_admin/mn_logs/collect_info/mn_logs_collect_info_form.html'
    })
    .state('app.admin.settings', {
      url: '/settings',
      abstract: true,
      templateUrl: 'mn_admin/mn_settings/mn_settings.html'
    })
    .state('app.admin.settings.cluster', {
      url: '/cluster',
      controller: 'mnSettingsClusterController',
      templateUrl: 'mn_admin/mn_settings/cluster/mn_settings_cluster.html'
    })
    .state('app.admin.settings.notifications', {
      url: '/notifications',
      controller: 'mnSettingsNotificationsController as mnSettingsNotificationsController',
      templateUrl: 'mn_admin/mn_settings/notifications/mn_settings_notifications.html'
    })
    .state('app.admin.settings.autoFailover', {
      url: '/autoFailover',
      controller: 'mnSettingsAutoFailoverController',
      templateUrl: 'mn_admin/mn_settings/auto_failover/mn_settings_auto_failover.html'
    })
    .state('app.admin.settings.alerts', {
      url: '/alerts',
      controller: 'mnSettingsAlertsController',
      templateUrl: 'mn_admin/mn_settings/alerts/mn_settings_alerts.html'
    })
    .state('app.admin.settings.autoCompaction', {
      url: '/autoCompaction',
      controller: 'mnSettingsAutoCompactionController',
      templateUrl: 'mn_admin/mn_settings/auto_compaction/mn_settings_auto_compaction.html'
    })
    .state('app.admin.settings.ldap', {
      url: '/ldap',
      controller: 'mnSettingsLdapController as mnSettingsLdapController',
      templateUrl: 'mn_admin/mn_settings/ldap/mn_settings_ldap.html'
    })
    .state('app.admin.settings.sampleBuckets', {
      url: '/sampleBuckets',
      controller: 'mnSettingsSampleBucketsController as mnSettingsSampleBucketsController',
      templateUrl: 'mn_admin/mn_settings/sample_buckets/mn_settings_sample_buckets.html'
    })
    .state('app.admin.settings.accountManagement', {
      url: '/accountManagement',
      controller: 'mnAccountManagementController as mnAccountManagementController',
      templateUrl: 'mn_admin/mn_settings/account_management/mn_account_management.html',
      data: {
        required: {
          admin: true
        }
      }
    })
    .state('app.admin.settings.audit', {
      url: '/audit',
      controller: 'mnSettingsAuditController',
      templateUrl: 'mn_admin/mn_settings/audit/mn_settings_audit.html'
    });
});