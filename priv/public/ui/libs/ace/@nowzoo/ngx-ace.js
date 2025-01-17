import ace from '../ace.js';
import "/ui/web_modules/common/tslib.es6-c4a4947b.js";
import "/ui/web_modules/common/mergeMap-64c6f393.js";
import "/ui/web_modules/common/merge-183efbc7.js";
import "/ui/web_modules/common/forkJoin-269e2e92.js";
import "/ui/web_modules/common/share-d41e3509.js";
import {
    InjectionToken as e,
    Injectable as t,
    Inject as o,
    defineInjectable as r,
    inject as n,
    Component as i,
    forwardRef as s,
    ElementRef as a,
    NgZone as d,
    Input as u,
    Output as c,
    EventEmitter as p,
    NgModule as h
} from "/ui/web_modules/@angular/core.js";
import "/ui/web_modules/@angular/common.js";
import "/ui/web_modules/@angular/platform-browser.js";
import {
  NG_VALUE_ACCESSOR as l
} from "/ui/web_modules/@angular/forms.js";
var m = {
        aceURL: ".."
    },
    f = new e("options for ngx-ace"),
    g = function() {
        function e(e) {
            this._options = e, this._loadedPromise = null
        }
        return Object.defineProperty(e.prototype, "aceURL", {
            get: function() {
                return this._options.aceURL
            },
            enumerable: !0,
            configurable: !0
        }), Object.defineProperty(e.prototype, "defaultEditorOptions", {
            get: function() {
                return this._options.defaultEditorOptions || null
            },
            enumerable: !0,
            configurable: !0
        }), e.prototype.loaded = function() {
          return(Promise.resolve()); // no need to load ace since it is imported above
//            var e = this;
//            return this._loadedPromise || (this._loadedPromise = new Promise((function(t, o) {
//                var r = document.createElement("script");
//                r.onload = function() {
//                    ace.config.set("basePath", e.aceURL), t()
//                }, r.onerror = o, r.src = e.aceURL + "/ace.js", document.body.appendChild(r)
//            }))), this._loadedPromise
        }, e.decorators = [{
            type: t,
            args: [{
                providedIn: "root"
            }]
        }], e.ctorParameters = function() {
            return [{
                type: void 0,
                decorators: [{
                    type: o,
                    args: [f]
                }]
            }]
        }, e.ngInjectableDef = r({
            factory: function() {
                return new e(n(f))
            },
            token: e,
            providedIn: "root"
        }), e
    }(),
    y = function() {
        function e(e, t, o) {
            this._service = e, this._elementRef = t, this._zone = o, this.mode = null, this.theme = null, this.ready = new p, this._editor = null, this._value = "", this._disabled = !1, this.propagateChange = function() {}, this.propagateTouched = function() {}
        }
        return Object.defineProperty(e.prototype, "service", {
            get: function() {
                return this._service
            },
            enumerable: !0,
            configurable: !0
        }), Object.defineProperty(e.prototype, "editor", {
            get: function() {
                return this._editor
            },
            enumerable: !0,
            configurable: !0
        }), Object.defineProperty(e.prototype, "session", {
            get: function() {
                return this.editor.session
            },
            enumerable: !0,
            configurable: !0
        }), e.prototype.writeValue = function(e) {
            if (this._value = e || "", this.editor) {
                var t = this.editor.getCursorPosition();
                this.editor.setValue(this._value, -1), this.editor.moveCursorToPosition(t)
            }
        }, e.prototype.registerOnChange = function(e) {
            this.propagateChange = e
        }, e.prototype.registerOnTouched = function(e) {
            this.propagateTouched = e
        }, e.prototype.setDisabledState = function(e) {
            this._disabled = e, this.editor && this.editor.setReadOnly(e)
        }, e.prototype.ngOnInit = function() {
            var t = this;
            this._zone.runOutsideAngular((function() {
                t.service.loaded().then((function() {
                    t._zone.run((function() {
                        t.id = "ngx-ace-" + ++e.counter, t._editor = ace.edit(t._elementRef.nativeElement), t.service.defaultEditorOptions && t.editor.setOptions(t.service.defaultEditorOptions), t.editor.setReadOnly(t._disabled), t.onModeChanged(), t.onThemeChanged(), t.editor.setValue(t._value, -1), t.editor.on("change", t.onEditorValueChange.bind(t)), t.editor.on("blur", t.onEditorBlurred.bind(t)), t.ready.emit(t.editor)
                    }))
                }))
            }))
        }, e.prototype.ngOnChanges = function(e) {
            this.editor && (e.mode && this.onModeChanged(), e.theme && this.onThemeChanged())
        }, e.prototype.ngOnDestroy = function() {
            this.editor.destroy()
        }, e.prototype.onModeChanged = function() {
            this.mode && this.session.setMode("ace/mode/" + this.mode)
        }, e.prototype.onThemeChanged = function() {
            this.theme && this.editor.setTheme("ace/theme/" + this.theme)
        }, e.prototype.onEditorValueChange = function() {
            this.propagateChange(this.editor.getValue())
        }, e.prototype.onEditorBlurred = function() {
            this.propagateTouched(this.editor.getValue())
        }, e.counter = 0, e.decorators = [{
            type: i,
            args: [{
                selector: "ngx-ace",
                exportAs: "ngxAce",
                template: "",
                providers: [{
                    provide: l,
                    useExisting: s((function() {
                        return e
                    })),
                    multi: !0
                }],
                styles: [":host {display: block; width: 100%; height: 100%}"]
            }]
        }], e.ctorParameters = function() {
            return [{
                type: g
            }, {
                type: a
            }, {
                type: d
            }]
        }, e.propDecorators = {
            mode: [{
                type: u
            }],
            theme: [{
                type: u
            }],
            ready: [{
                type: c
            }]
        }, e
    }(),
    b = function() {
        function e() {}
        return e.forRoot = function() {
            return {
                ngModule: e,
                providers: [{
                    provide: f,
                    useValue: m
                }, g]
            }
        }, e.decorators = [{
            type: h,
            args: [{
                declarations: [y],
                imports: [],
                exports: [y]
            }]
        }], e
    }();
export {
  m as DEFAULT_NGX_ACE_OPTIONS, f as NGX_ACE_OPTIONS, y as NgxAceComponent, b as NgxAceModule, g as NgxAceService,
  ace as ace
};
//# sourceMappingURL=ngx-ace.js.map
