
s2 = {};

// Constructor for Layer objects
s2.Layer = function() {
    this.info = {};
    this.func = {};
    this.set = {};
    this.classchild = {};
    this.prop = [];        // Declared property names, in order (including property use)
    this.propgroup = {};   // Propgroup Metadata
    this.propgrouplist = []; // Declared propgroup names, in order
    this.propmeta = {};    // Property metadata
    this.prophide = {};    // propname => true if hide in effect at this layer
    this.haspropgroups = false;
};
s2.Layer.prototype = {
    setLayerInfo: function (key, value) {
        this.info[key] = value;
    },
    getLayerInfo: function (key) {
        if (key) {
            return this.info[key];
        }
        else {
            return this.info;
        }
    },
    registerClass: function (name, parent) {
        this.classchild[name] = [];
        if (parent) {
            this.classchild[parent].push(name);
        }
    },
    registerFunction: function (names, cons) {
        var func = cons();
        for (var i = 0; i < names.length; i++) {
            this.func[names[i]] = cons();
        }
    },
    registerProperty: function (name, type, attr) {
        this.propmeta[name] = {
            'name': name,
            'type': type,
            'attr': attr
        };
        this.prop.push(name);
    },
    registerPropGroup: function (name, members) {
        if (!this.propgroup[name]) this.propgroup[name] = {};
        this.propgroup[name].name = name;
        if (!this.propgroup[name].displayname)
            this.propgroup[name].displayname = name;
        this.propgroup[name].members = members;
        this.haspropgroups = true;
        this.propgrouplist.push(this.propgroup[name]);
    },
    namePropGroup: function (name, displayname) {
        if (!this.propgroup[name]) this.propgroup[name] = {};
        this.propgroup[name].name = name;
        this.propgroup[name].displayname = displayname;
    },
    setProperty: function (name, val) {
        this.set[name] = val;
    },
    useProperty: function (name) {
        this.prop.push(name);
    },
    hideProperty: function (name) {
        this.prophide[name] = true;
    },
    toString: function() {
        return this.getLayerInfo("name") || "unnamed layer";
    }
};

// Constructor for Context objects
s2.Context = function(layerList) {
    this.func = {};
    this.prop = {};
    this.core = undefined;
    this.layout = undefined;
    for (var i = 0; i < layerList.length; i++) {
        var lay = layerList[i];

        // If you have more than one core or layout in the context
        // this will break, but that's a stupid thing to do anyway.
        if (lay.info.type == "core") this.core = i;
        if (lay.info.type == "layout") this.layout = i;

        for (funcname in lay.func) {
            this.func[funcname] = lay.func[funcname];
        }
        
        // TODO: Also do property sets
        for (propname in lay.set) {
            this.prop[propname] = lay.set[propname];
        }
    }
    
    // Which layer dictates property ordering?
    this.propmaster = this.layout != undefined ? this.layout : this.core;

    this.layerList = layerList;
    this.builtin = {};
};
s2.Context.prototype = {
    print: function(str) {},
    setPrint: function(func) {
        this.print = func;
    },
    setBuiltin: function(obj) {
        this.builtin = obj;
    },
    getFunction: function(name) {
        return this.func[name];
    },
    getMethod: function(obj, name, layer, line) {
        if (! obj || obj[".isnull"]) {
            throw "Method "+name+" called on null object "+
                  "in "+layer+", at line "+line;
        }
        var cla = obj[".type"];
        return this.getFunction(cla+"::"+name);
    },
    runFunction: function(name) {
        var funcargs = [ this ];
        for (var i = 1; i < arguments.length; i++) {
            funcargs.push(arguments[i]);
        }
        var func = this.getFunction(name);
        return func.apply(null, funcargs);
    },
    runMethod: function(obj, name) {
        var funcargs = [ this, obj ];
        for (var i = 2; i < arguments.length; i++) {
            funcargs.push(arguments[i]);
        }
        var func = this.getMethod(obj, name, null, 0);
        return func.apply(null, funcargs);
    },
    customizeUsesGroups: function () {
        return this.layerList[this.propmaster].haspropgroups;
    },
    _findCustomizeProp: function (propname) {
        for (var i = this.propmaster; i >= 0; i--) {
            var prop = this.layerList[i].propmeta[propname];
            if (prop != undefined) {
                return prop;
            }
        }
        return undefined;
    },
    getCustomizeProps: function () {
        var ret = [];
        var propmaster = this.layerList[this.propmaster];
        for (var i = 0; i < propmaster.prop.length; i++) {
            var prop = this._findCustomizeProp(propmaster.prop[i]);
            if (prop != undefined) {
                ret.push(prop);
            }
        }
        return ret;
    },
    getCustomizePropGroups: function () {
        if (! this.layerList[this.propmaster].haspropgroups) return undefined;
        var ret = [];
        var propmaster = this.layerList[this.propmaster];
        for (var i = 0; i < propmaster.propgrouplist.length; i++) {
            var propgroup = propmaster.propgrouplist[i];
            var members = [];
            var retpg = {
                name: propgroup.name,
                displayname: propgroup.displayname,
                members: members
            };
            ret.push(retpg);

            for (var j = 0; j < propgroup.members.length; j++) {
                var prop = this._findCustomizeProp(propgroup.members[j]);
                if (prop != undefined) {
                    members.push(prop);
                }
            }
        }
        return ret;
    }
};

s2.makeLayer = function() {
    var ret = new s2.Layer;
    return new s2.Layer;
};
s2.makeContext = function(layerList) {
    return new s2.Context(layerList);
};

// Default runtime library functions
s2.runtime = {
    hashSize: function (h) {
        var ret = 0;
        for (k in h) { ret++ };
        return ret;
    },
    isDefined: function (v) {
        if (v == undefined) return false;
        if (v[".isnull"]) return false;
        return true;
    },
    hashToBool: function (h) {
        return (s2.runtime.hashSize(h) != 0);
    },
    noTags: function (s) {
        s = s.replace(/</g, "&lt;");
        s = s.replace(/>/g, "&gt;");
        return s;
    },
    makeRange: function (n1, n2) {
        var ret = [];
        for (var i = n1; i <= n2; i++) {
            ret.push(i);
        }
        return ret;
    },
    reverseArray: function (a) {
        // JavaScript's Array.reverse does the reverse in-place,
        // which isn't correct for S2's reverse operator.
        var ret = [];
        for (var i = a.length; i >= 0; i--) {
            ret.push(a[i]);
        }
        return ret;
    },
    reverseString: function (s) {
        // FIXME: There is probably a better way to do this.
        var ret = "";
        for (var i = s.length; i >= 0; i--) {
            ret = ret.concat(s.charAt(i));
        }
        return ret;
    }
};

s2.builtin = {};
s2.setBuiltin = function (obj) {
    s2.builtin = obj;
};

