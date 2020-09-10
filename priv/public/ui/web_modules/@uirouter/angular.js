import{_ as ee,a as te,c as ne,b as re,g as ie}from"../common/tslib.es6-c4a4947b.js";import{g as se,e as oe}from"../common/mergeMap-64c6f393.js";import"../common/merge-183efbc7.js";import{a as ue,B as ce,c as pe}from"../common/concat-981db672.js";import"../common/Notification-9e07e457.js";import{R as fe}from"../common/ReplaySubject-8316d9c1.js";import{o as le}from"../common/filter-d76a729c.js";import"../common/share-d41e3509.js";import{s as he}from"../common/switchMap-c513d696.js";import{ComponentFactoryResolver as de,ReflectiveInjector as ge,ViewChild as me,ViewContainerRef as ve,Input as ye,Component as _e,Inject as Se,Directive as we,HostListener as Re,Optional as Ce,Output as Ue,ContentChildren as xe,Host as Ee,Self as Oe,InjectionToken as Pe,ANALYZE_FOR_ENTRY_COMPONENTS as je,APP_INITIALIZER as Te,NgModule as Ie,NgModuleFactoryLoader as ke,Compiler as Ne,NgModuleFactory as $e,PLATFORM_ID as Ve,Injector as De,ElementRef as Fe,Renderer2 as Ae,EventEmitter as He,QueryList as qe}from"../@angular/core.js";import{LocationStrategy as Me,HashLocationStrategy as Le,PathLocationStrategy as Be,CommonModule as ze,isPlatformBrowser as Je}from"../@angular/common.js";import{p as Ge,f as Ke,V as Qe,s as We,a as Xe,i as Ye,R as Ze,u as et,b as tt,t as nt,N as rt,c as it,d as st,e as ot,g as ut,h as ct,j as pt,P as ft,k as lt,T as ht,l as dt,U as gt,m as mt,n as vt,B as yt,o as _t,S as St,q as wt,r as Rt,v as Ct,w as Ut,x as xt,y as Et,z as Ot,A as Pt,C as jt}from"../common/interface-c1256a29.js";export{bu as $injector,bt as $q,B as BaseLocationServices,bs as BaseUrlRule,z as BrowserLocationConfig,aY as Category,a_ as DefType,ak as Glob,bv as HashLocationService,bd as HookBuilder,by as MemoryLocationConfig,bw as MemoryLocationService,N as NATIVE_INJECTOR_TOKEN,C as Param,bq as ParamFactory,b1 as ParamType,a$ as ParamTypes,b2 as PathNode,P as PathUtils,bx as PushStateLocationService,aI as Queue,bf as RegisteredHook,bh as RejectType,bi as Rejection,m as Resolvable,R as ResolveContext,b6 as StateBuilder,b8 as StateMatcher,b7 as StateObject,b0 as StateParams,b9 as StateQueueManager,S as StateRegistry,q as StateService,ba as TargetState,aZ as Trace,bj as Transition,bl as TransitionEventType,bk as TransitionHook,bb as TransitionHookPhase,bc as TransitionHookScope,T as TransitionService,U as UIRouter,x as UIRouterGlobals,bG as UIRouterPluginBase,bo as UrlConfig,bp as UrlMatcher,r as UrlMatcherFactory,v as UrlRouter,br as UrlRuleFactory,bn as UrlRules,w as UrlService,V as ViewService,ag as _extend,_ as _inArray,O as _pushTo,L as _removeFrom,at as all,a4 as allTrueR,Y as ancestors,ar as and,au as any,k as anyTrueR,ae as applyPairs,ad as arrayTuples,ab as assertFn,aa as assertMap,a9 as assertPredicate,aP as beforeAfterSubstr,bB as buildUrl,am as compose,af as copy,I as createProxyFunctions,al as curry,b4 as defaultResolvePolicy,bm as defaultTransOpts,W as defaults,Q as deregAll,av as eq,G as equals,e as extend,b as filter,a0 as find,a8 as flatten,a5 as flattenR,aN as fnToString,f as forEach,E as fromJson,aM as functionToString,bA as getParams,bD as hashLocationPlugin,aQ as hostRegex,h as identity,c as inArray,J as inherit,ax as invoke,y as is,aD as isArray,aE as isDate,d as isDefined,i as isFunction,aG as isInjectable,aA as isNull,aB as isNullOrUndefined,g as isNumber,aC as isObject,aH as isPromise,aF as isRegExp,l as isString,az as isUndefined,aX as joinNeighborsR,aL as kebobString,bz as keyValsToObjectR,bC as locationPluginFactory,bg as makeEvent,aj as makeStub,a2 as map,a1 as mapObj,be as matchState,aJ as maxLength,bF as memoryLocationPlugin,X as mergeR,H as noop,aq as not,Z as omit,as as or,aK as padString,ac as pairs,a as parse,n as parseUrl,ay as pattern,p as pick,an as pipe,$ as pluck,ao as prop,ap as propEq,a6 as pushR,bE as pushStateLocationPlugin,M as pushTo,K as removeFrom,b5 as resolvablesBuilder,b3 as resolvePolicies,D as root,s as services,o as servicesPlugin,ah as silenceUncaughtInPromise,ai as silentRejection,aU as splitEqual,aS as splitHash,aW as splitOnDelim,aT as splitQuery,aO as stringify,aR as stripLastPathElement,A as tail,F as toJson,t as trace,aV as trimHashVal,j as uniqR,a7 as unnest,u as unnestR,aw as val,a3 as values}from"../common/interface-c1256a29.js";import{U as Tt}from"../common/ui-router-rx-04f7f595.js";function It(e){var t={},n=e.views||{$default:Ge(e,["component","bindings"])};return Ke(n,(function(n,r){if(r=r||"$default",Ye(n)&&(n={component:n}),0!==Object.keys(n).length){n.$type="ng2",n.$context=e,n.$name=r;var a=Qe.normalizeUIViewTarget(n.$context,n.$name);n.$uiViewName=a.uiViewName,n.$uiViewContextAnchor=a.uiViewContextAnchor,t[r]=n}})),t}var kt=0,Nt=function(){function e(e,t){this.path=e,this.viewDecl=t,this.$id=kt++,this.loaded=!0}return e.prototype.load=function(){return We.$q.when(this)},e}(),$t=function(){function e(){for(var e=[],t=0;t<arguments.length;t++)e[t]=arguments[t];if(e.length<2)throw new Error("pass at least two injectors");this.injectors=e}return e.prototype.get=function(t,n){for(var r=0;r<this.injectors.length;r++){var a=this.injectors[r].get(t,e.NOT_FOUND);if(a!==e.NOT_FOUND)return a}if(arguments.length>=2)return n;this.injectors[0].get(t)},e.NOT_FOUND={},e}(),Vt=0,Dt=function(e){return e.inputs.map((function(e){return{prop:e.propName,token:e.templateName}}))},Ft=Dt,At=function(){function e(e,t,n){this.router=e,this.viewContainerRef=n,this._uiViewData={},this._parent=t}var t;return t=e,Object.defineProperty(e.prototype,"_name",{set:function(e){this.name=e},enumerable:!0,configurable:!0}),Object.defineProperty(e.prototype,"state",{get:function(){return Xe("_uiViewData.config.viewDecl.$context.self")(this)},enumerable:!0,configurable:!0}),e.prototype.ngOnInit=function(){var e=this,t=this.router,n=this._parent.fqn,r=this.name||"$default";this._uiViewData={$type:"ng2",id:Vt++,name:r,fqn:n?n+"."+r:r,creationContext:this._parent.context,configUpdated:this._viewConfigUpdated.bind(this),config:void 0},this._deregisterUiCanExitHook=t.transitionService.onBefore({},(function(t){return e._invokeUiCanExitHook(t)})),this._deregisterUiOnParamsChangedHook=t.transitionService.onSuccess({},(function(t){return e._invokeUiOnParamsChangedHook(t)})),this._deregisterUIView=t.viewService.registerUIView(this._uiViewData)},e.prototype._invokeUiCanExitHook=function(e){var t=this._componentRef&&this._componentRef.instance,n=t&&t.uiCanExit;if(Ye(n)){var r=this.state;-1!==e.exiting().indexOf(r)&&e.onStart({},(function(){return n.call(t,e)}))}},e.prototype._invokeUiOnParamsChangedHook=function(e){var t=this._componentRef&&this._componentRef.instance,n=t&&t.uiOnParamsChanged;if(Ye(n)){var r=this.state;if(e===new Ze(this._uiViewData.config.path).getResolvable("$transition$").data||-1!==e.exiting().indexOf(r))return;var a=e.params("to"),i=e.params("from"),s=function(e){return e.paramSchema},o=e.treeChanges("to").map(s).reduce(et,[]),u=e.treeChanges("from").map(s).reduce(et,[]),c=o.filter((function(e){var t=u.indexOf(e);return-1===t||!u[t].type.equals(a[e.id],i[e.id])}));if(c.length){var p=c.map((function(e){return e.id})),f=tt(a,(function(e,t){return-1!==p.indexOf(t)}));t.uiOnParamsChanged(f,e)}}},e.prototype._disposeLast=function(){this._componentRef&&this._componentRef.destroy(),this._componentRef=null},e.prototype.ngOnDestroy=function(){this._deregisterUIView&&this._deregisterUIView(),this._deregisterUiCanExitHook&&this._deregisterUiCanExitHook(),this._deregisterUiOnParamsChangedHook&&this._deregisterUiOnParamsChangedHook(),this._deregisterUIView=this._deregisterUiCanExitHook=this._deregisterUiOnParamsChangedHook=null,this._disposeLast()},e.prototype._viewConfigUpdated=function(e){if(!e)return this._disposeLast();e instanceof Nt&&this._uiViewData.config!==e&&(this._disposeLast(),nt.traceUIViewConfigUpdated(this._uiViewData,e&&e.viewDecl.$context),this._applyUpdatedConfig(e),this._componentRef.changeDetectorRef.markForCheck())},e.prototype._applyUpdatedConfig=function(e){this._uiViewData.config=e;var t=new Ze(e.path),n=this._getComponentInjector(t),r=e.viewDecl.component,a=n.get(de).resolveComponentFactory(r);this._componentRef=this._componentTarget.createComponent(a,void 0,n),this._applyInputBindings(a,this._componentRef.instance,t,r)},e.prototype._getComponentInjector=function(e){var n=e.getTokens().map((function(t){return e.getResolvable(t)})).filter((function(e){return e.resolved})).map((function(t){return{provide:t.token,useValue:e.injector().get(t.token)}})),r={context:this._uiViewData.config.viewDecl.$context,fqn:this._uiViewData.fqn};n.push({provide:t.PARENT_INJECT,useValue:r});var a=this.viewContainerRef.injector,i=e.getResolvable(rt).data,s=new $t(i,a);return ge.resolveAndCreate(n,s)},e.prototype._applyInputBindings=function(e,t,n,r){var a=this._uiViewData.config.viewDecl.bindings||{},i=Object.keys(a),s=i.reduce((function(t,n){return t.concat([{prop:(r=n,i=e.inputs.find((function(e){return e.templateName===r})),i&&i.propName||r),token:a[n]}]);var r,i}),[]),o=Dt(e).filter((function(e){return!it(i,e.prop)})),u=n.injector();s.concat(o).map((function(e){return{prop:e.prop,resolvable:n.getResolvable(e.token)}})).filter((function(e){return e.resolvable&&e.resolvable.resolved})).forEach((function(e){t[e.prop]=u.get(e.resolvable.token)}))},e.PARENT_INJECT="UIView.PARENT_INJECT",ee([me("componentTarget",{read:ve,static:!0}),te("design:type",ve)],e.prototype,"_componentTarget",void 0),ee([ye("name"),te("design:type",String)],e.prototype,"name",void 0),ee([ye("ui-view"),te("design:type",String),te("design:paramtypes",[String])],e.prototype,"_name",null),e=t=ee([_e({selector:"ui-view, [ui-view]",exportAs:"uiView",template:'\n    <ng-template #componentTarget></ng-template>\n    <ng-content *ngIf="!_componentRef"></ng-content>\n  '}),ne(1,Se(t.PARENT_INJECT)),te("design:paramtypes",[gt,Object,ve])],e)}();function Ht(e,t,n){return void 0===n&&(n={}),Ye(n.config)&&n.config(e,t,n),(n.states||[]).map((function(t){return e.stateRegistry.register(t)}))}function qt(e,t,n){st(n.deferIntercept)&&e.urlService.deferIntercept(n.deferIntercept),st(n.otherwise)&&e.urlService.rules.otherwise(n.otherwise),st(n.initial)&&e.urlService.rules.initial(n.initial)}var Mt=function(){function e(e,t){this._el=e,this._renderer=t}return e.prototype.openInNewTab=function(){return"_blank"===this._el.nativeElement.target},e.prototype.update=function(e){e&&""!==e?this._renderer.setProperty(this._el.nativeElement,"href",e):this._renderer.removeAttribute(this._el.nativeElement,"href")},e=ee([we({selector:"a[uiSref]"}),te("design:paramtypes",[Fe,Ae])],e)}(),Lt=function(){function e(e,t,n){var r=this;this.targetState$=new fe(1),this._emit=!1,this._router=e,this._anchorUISref=t,this._parent=n,this._statesSub=e.globals.states$.subscribe((function(){return r.update()}))}return Object.defineProperty(e.prototype,"uiSref",{set:function(e){this.state=e,this.update()},enumerable:!0,configurable:!0}),Object.defineProperty(e.prototype,"uiParams",{set:function(e){this.params=e,this.update()},enumerable:!0,configurable:!0}),Object.defineProperty(e.prototype,"uiOptions",{set:function(e){this.options=e,this.update()},enumerable:!0,configurable:!0}),e.prototype.ngOnInit=function(){this._emit=!0,this.update()},e.prototype.ngOnChanges=function(e){this.update()},e.prototype.ngOnDestroy=function(){this._emit=!1,this._statesSub.unsubscribe(),this.targetState$.unsubscribe()},e.prototype.update=function(){var e=this._router.stateService;if(this._emit){var t=e.target(this.state,this.params,this.getOptions());this.targetState$.next(t)}if(this._anchorUISref){var n=e.href(this.state,this.params,this.getOptions());this._anchorUISref.update(n)}},e.prototype.getOptions=function(){var e={relative:this._parent&&this._parent.context&&this._parent.context.name,inherit:!0,source:"sref"};return ot(e,this.options||{})},e.prototype.go=function(e,t,n){if(!(this._anchorUISref&&(this._anchorUISref.openInNewTab()||e||!ut(e)||t||n)||!this.state))return this._router.stateService.go(this.state,this.params,this.getOptions()),!1},ee([ye("uiSref"),te("design:type",String)],e.prototype,"state",void 0),ee([ye("uiParams"),te("design:type",Object)],e.prototype,"params",void 0),ee([ye("uiOptions"),te("design:type",Object)],e.prototype,"options",void 0),ee([Re("click",["$event.button","$event.ctrlKey","$event.metaKey"]),te("design:type",Function),te("design:paramtypes",[Number,Boolean,Boolean]),te("design:returntype",void 0)],e.prototype,"go",null),e=ee([we({selector:"[uiSref]",exportAs:"uiSref"}),ne(1,Ce()),ne(2,Se(At.PARENT_INJECT)),te("design:paramtypes",[gt,Mt,Object])],e)}(),Bt={active:!1,exact:!1,entering:!1,exiting:!1,targetStates:[]};function zt(e,t){return t.map((function(n){return e.concat(ft.subPath(t,(function(e){return e.state===n.state})))}))}function Jt(e,t){var n=function(e){if(!e.exists())return function(){return!1};var t=e.$state(),n=e.params(),r=ft.buildPath(e).map((function(e){return e.paramSchema})).reduce(et,[]).filter((function(e){return n.hasOwnProperty(e.id)}));return function(e){var a=Pt(e);if(!a||a.state!==t)return!1;var i=ft.paramValues(e);return jt.equals(r,i,n)}}(t),r=e.trans.treeChanges(),a="start"===e.evt,i="success"===e.evt?r.to:r.from;return{active:zt([],i).map(n).reduce(lt,!1),exact:n(i),entering:!!a&&zt(r.retained,r.entering).map(n).reduce(lt,!1),exiting:!!a&&zt(r.retained,r.exiting).map(n).reduce(lt,!1),targetStates:[t]}}function Gt(e,t){return{active:e.active||t.active,exact:e.exact||t.exact,entering:e.entering||t.entering,exiting:e.exiting||t.exiting,targetStates:e.targetStates.concat(t.targetStates)}}var Kt=function(){function e(e,t){this.uiSrefStatus=new He(!1),this._globals=t,this._hostUiSref=e,this.status=Object.assign({},Bt)}return e.prototype.ngAfterContentInit=function(){var e=this,t=this._globals.start$.pipe(he((function(e){var t=function(t){return{evt:t,trans:e}},n=le(t("start")),r=e.promise.then((function(){return t("success")}),(function(){return t("error")})),a=se(r);return ue(n,a)}))),n=function(t){return t.concat(e._hostUiSref).filter(ct).reduce(pt,[])};this._srefs$=new ce(n(this._srefs.toArray())),this._srefChangesSub=this._srefs.changes.subscribe((function(t){return e._srefs$.next(n(t))}));var r=this._srefs$.pipe(he((function(e){return pe(e.map((function(e){return e.targetState$})))})));this._subscription=t.pipe(he((function(e){return r.pipe(oe((function(t){return t.map((function(t){return Jt(e,t)})).reduce(Gt)})))}))).subscribe(this._setStatus.bind(this))},e.prototype.ngOnDestroy=function(){this._subscription&&this._subscription.unsubscribe(),this._srefChangesSub&&this._srefChangesSub.unsubscribe(),this._srefs$&&this._srefs$.unsubscribe(),this._subscription=this._srefChangesSub=this._srefs$=void 0},e.prototype._setStatus=function(e){this.status=e,this.uiSrefStatus.emit(e)},ee([Ue("uiSrefStatus"),te("design:type",Object)],e.prototype,"uiSrefStatus",void 0),ee([xe(Lt,{descendants:!0}),te("design:type",qe)],e.prototype,"_srefs",void 0),e=ee([we({selector:"[uiSrefStatus],[uiSrefActive],[uiSrefActiveEq]",exportAs:"uiSrefStatus"}),ne(0,Ee()),ne(0,Oe()),ne(0,Ce()),te("design:paramtypes",[Lt,xt])],e)}(),Qt=function(){function e(e,t,n){var r=this;this._classes=[],this._classesEq=[],this._subscription=e.uiSrefStatus.subscribe((function(e){r._classes.forEach((function(r){e.active?t.addClass(n.nativeElement,r):t.removeClass(n.nativeElement,r)})),r._classesEq.forEach((function(r){e.exact?t.addClass(n.nativeElement,r):t.removeClass(n.nativeElement,r)}))}))}return Object.defineProperty(e.prototype,"active",{set:function(e){this._classes=e.split(/\s+/)},enumerable:!0,configurable:!0}),Object.defineProperty(e.prototype,"activeEq",{set:function(e){this._classesEq=e.split(/\s+/)},enumerable:!0,configurable:!0}),e.prototype.ngOnDestroy=function(){this._subscription.unsubscribe()},ee([ye("uiSrefActive"),te("design:type",String),te("design:paramtypes",[String])],e.prototype,"active",null),ee([ye("uiSrefActiveEq"),te("design:type",String),te("design:paramtypes",[String])],e.prototype,"activeEq",null),e=ee([we({selector:"[uiSrefActive],[uiSrefActiveEq]"}),ne(2,Ee()),te("design:paramtypes",[Kt,Ae,Fe])],e)}(),Wt=[Lt,Mt,At,Qt,Kt],Xt=Wt,Yt=new Pe("UIRouter Root Module"),Zt=new Pe("UIRouter Module"),en=new Pe("UIRouter States");function tn(e,t){var n=t[0];return n&&n.deferInitialRender?function(){return new Promise((function(t){e.onStart({},(function(e){e.promise.then(t,t)}),{invokeLimit:1})}))}:function(){return Promise.resolve()}}function nn(e){return[{provide:Yt,useValue:e,multi:!0},{provide:Zt,useValue:e,multi:!0},{provide:je,useValue:e.states||[],multi:!0},{provide:Te,useFactory:tn,deps:[ht,Yt],multi:!0}]}function rn(e){return[{provide:Zt,useValue:e,multi:!0},{provide:je,useValue:e.states||[],multi:!0}]}function sn(e){return{provide:Me,useClass:e?Le:Be}}var on=function(){function e(){}var t;return t=e,e.forRoot=function(e){return void 0===e&&(e={}),{ngModule:t,providers:ie([yn,On,sn(e.useHash)],nn(e))}},e.forChild=function(e){return void 0===e&&(e={}),{ngModule:t,providers:rn(e)}},e=t=ee([Ie({imports:[ze],declarations:[Wt],exports:[Wt],entryComponents:[At]})],e)}();function un(e){return function(t,n){var r=t.injector().get(rt);return cn(e,r).then((function(e){return e.create(r)})).then((function(e){return pn(t,e,r,n)}))}}function cn(e,t){if(dt(e))return t.get(ke).load(e);var n=t.get(Ne);return Promise.resolve(e()).then((function(e){return e&&e.__esModule&&e.default?e.default:e})).then((function(e){return e instanceof $e?e:n.compileModuleAsync(e)}))}function pn(e,t,n,r){var a=t.injector,i=a.get(gt),s=i.stateRegistry,o=r.name,u=s.get(o),c=/^(.*)\.\*\*$/.exec(o),p=c&&c[1],f=fn(n,a,Yt).reduce(pt,[]),l=fn(n,a,Zt).reduce(pt,[]);if(f.length)throw console.log(f),new Error("Lazy loaded modules should not contain a UIRouterModule.forRoot() module");var h=l.map((function(e){return Ht(i,a,e)})).reduce(et,[]).reduce(pt,[]);if(c){var d=s.get(p);if(!d||d===u)throw new Error("The Future State named '"+o+"' lazy loaded an NgModule. The lazy loaded NgModule must have a state named '"+p+"' which replaces the (placeholder) '"+o+"' Future State. Add a '"+p+"' state to the lazy loaded NgModule using UIRouterModule.forChild({ states: CHILD_STATES }).")}return h.filter((function(e){return!it(h,e.parent)})).forEach((function(e){return e.resolvables.push(mt.fromData(rt,a))})),{}}function fn(e,t,n){var r=t.get(n,[]),a=e.get(n,[]);return r.filter((function(e){return-1===a.indexOf(e)}))}function ln(e,t){var n=e.loadChildren;return n?un(n):e.lazyLoad}var hn=function(e){function t(t,n,r){var a=e.call(this,t,r)||this;return a._locationStrategy=n,a._locationStrategy.onPopState((function(e){"hashchange"!==e.type&&a._listener(e)})),a}return re(t,e),t.prototype._get=function(){return this._locationStrategy.path(!0).replace(this._locationStrategy.getBaseHref().replace(/\/$/,""),"")},t.prototype._set=function(e,t,n,r){var a=vt(n),i=a.path,s=a.search,o=a.hash,u=i+(o?"#"+o:"");r?this._locationStrategy.replaceState(e,t,u,s):this._locationStrategy.pushState(e,t,u,s)},t.prototype.dispose=function(t){e.prototype.dispose.call(this,t)},t}(yt),dn=function(e){function t(t,n){var r=e.call(this,t,Et(Be)(n))||this;return r._locationStrategy=n,r}return re(t,e),t.prototype.baseHref=function(e){return this._locationStrategy.getBaseHref()},t}(Ot);function gn(e,t,n,r){if(1!==t.length)throw new Error("Exactly one UIRouterModule.forRoot() should be in the bootstrapped app module's imports: []");var a=new gt;a.plugin(Tt),a.plugin(_t),We.$injector.get=r.get.bind(r),a.locationService=new hn(a,e,Je(r.get(Ve))),a.locationConfig=new dn(a,e);a.viewService._pluginapi._viewConfigFactory("ng2",(function(e,t){return new Nt(e,t)}));var i=a.stateRegistry;i.decorator("views",It),i.decorator("lazyLoad",ln);var s=mt.fromData(rt,r);return i.root().resolvables.push(s),a.urlMatcherFactory.$get(),t.forEach((function(e){return qt(a,0,e)})),n.forEach((function(e){return Ht(a,r,e)})),a}function mn(e){return function(){e.urlRouter.interceptDeferred||(e.urlService.listen(),e.urlService.sync())}}function vn(e){return{fqn:null,context:e.root()}}var yn=[{provide:gt,useFactory:gn,deps:[Me,Yt,Zt,De]},{provide:At.PARENT_INJECT,useFactory:vn,deps:[St]},{provide:Te,useFactory:mn,deps:[gt],multi:!0}];function _n(e){return e.stateService}function Sn(e){return e.transitionService}function wn(e){return e.urlMatcherFactory}function Rn(e){return e.urlRouter}function Cn(e){return e.urlService}function Un(e){return e.viewService}function xn(e){return e.stateRegistry}function En(e){return e.globals}var On=[{provide:wt,useFactory:_n,deps:[gt]},{provide:ht,useFactory:Sn,deps:[gt]},{provide:Rt,useFactory:wn,deps:[gt]},{provide:Ct,useFactory:Rn,deps:[gt]},{provide:Ut,useFactory:Cn,deps:[gt]},{provide:Qe,useFactory:Un,deps:[gt]},{provide:St,useFactory:xn,deps:[gt]},{provide:xt,useFactory:En,deps:[gt]}],Pn=yn.concat(On);export{Mt as AnchorUISref,Nt as Ng2ViewConfig,Xt as UIROUTER_DIRECTIVES,Zt as UIROUTER_MODULE_TOKEN,Pn as UIROUTER_PROVIDERS,Yt as UIROUTER_ROOT_MODULE,en as UIROUTER_STATES,on as UIRouterModule,Lt as UISref,Qt as UISrefActive,Kt as UISrefStatus,At as UIView,Wt as _UIROUTER_DIRECTIVES,yn as _UIROUTER_INSTANCE_PROVIDERS,On as _UIROUTER_SERVICE_PROVIDERS,mn as appInitializer,Ht as applyModuleConfig,pn as applyNgModule,qt as applyRootModuleConfig,En as fnGlobals,xn as fnStateRegistry,_n as fnStateService,Sn as fnTransitionService,wn as fnUrlMatcherFactory,Rn as fnUrlRouter,Cn as fnUrlService,Un as fnViewService,cn as loadModuleFactory,un as loadNgModule,sn as locationStrategy,rn as makeChildProviders,nn as makeRootProviders,fn as multiProviderParentChildDelta,ln as ng2LazyLoadBuilder,It as ng2ViewsBuilder,tn as onTransitionReady,vn as parentUIViewInjectFactory,gn as uiRouterFactory,Ft as ɵ0};
//# sourceMappingURL=angular.js.map