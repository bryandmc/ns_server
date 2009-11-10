// Based on: http://ejohn.org/blog/javascript-micro-templating/
// Simple JavaScript Templating
// John Resig - http://ejohn.org/ - MIT Licensed
;(function(){
  var cache = {};

  this.tmpl = function tmpl(str, data){
    // Figure out if we're getting a template, or if we need to
    // load the template - and be sure to cache the result.

    var fn = !/\W/.test(str) && (cache[str] = cache[str] ||
                                 tmpl(document.getElementById(str).innerHTML));

    if (!fn) {
      var body = "var p=[],print=function(){p.push.apply(p,arguments);}," +
        "h=function(){return String(arguments[0]).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')};" +

      // Introduce the data as local variables using with(){}
      "with(obj){p.push('" +

      // Convert the template into pure JavaScript
      str
      .replace(/[\r\t\n]/g, " ")
      .split("{%").join("\t")
      .replace(/((^|%})[^\t]*)'/g, "$1\r") //'
      .replace(/\t=(.*?)%}/g, "',$1,'")
      .split("\t").join("');")
      .split("%}").join("p.push('")
      .split("\r").join("\\'")
        + "');}return p.join('');"

      // Generate a reusable function that will serve as a template
      // generator (and which will be cached).
      fn = new Function("obj", body);
    }

    // Provide some basic currying to the user
    return data ? fn( data ) : fn;
  };
})();

var StatGraphs = {
  update: function (stats) {
    var main = $('#overview_main_graph span')
    var ops = $('#overview_graph_ops')
    var gets = $('#overview_graph_gets')
    var sets = $('#overview_graph_sets')
    var misses = $('#overview_graph_misses')

    main.sparkline(stats.ops, {width: $(main.get(0).parentNode).innerWidth(), height: 200})
    ops.sparkline(stats.ops, {width: ops.innerWidth(), height: 100})
    gets.sparkline(stats.gets, {width: gets.innerWidth(), height: 100})
    sets.sparkline(stats.sets, {width: sets.innerWidth(), height: 100})
    misses.sparkline(stats.misses, {width: misses.innerWidth(), height: 100})
  }
}

$(function () {
  window.nav = {};

  nav.go = function (sec) {
    $.bbq.pushState({sec: sec});
  }

  $(window).bind('hashchange', function () {
    var sec = $.bbq.getState('sec') || 'overview';
    $('#middle_pane > div').css('display', 'none');
    $('#'+sec).css('display','block');
    setTimeout(function () {
      $(window).trigger('sec:' + sec);
    }, 10);
  });

  $(window).trigger('hashchange');

  function getStatsAsync(callback) {
    setTimeout(function () {
      callback({
        ops: [10, 5, 46, 100, 74, 25],
        gets: [25, 10, 5, 46, 100, 74],
        sets: [74, 25, 10, 5, 46, 100],
        misses: [100, 74, 25, 10, 5, 46],
        hot_keys: [{name:'user:image:value', type:'Persistent', gets: 10000, misses:100},
                   {name:'user:image:value2', type:'Cache', gets: 10000, misses:100},
                   {name:'user:image:value3', type:'Persistent', gets: 10000, misses:100},
                   {name:'user:image:value4', type:'Cache', gets: 10000, misses:100}]
      });
    }, 100);
  }

  $(window).bind('sec:overview', function () {
    getStatsAsync(function (stats) {
      StatGraphs.update(stats);
      var rows = $.map(stats.hot_keys, function (e) {
        return $.extend({}, e, {total: 0 + e.gets + e.misses});
      });
      $('#top_key_table_container').get(0).innerHTML = tmpl('top_keys_template', {rows:rows});
    });
  });
});
