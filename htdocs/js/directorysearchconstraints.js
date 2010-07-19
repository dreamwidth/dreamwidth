// the main view that contains the constraints
var DirectorySearchConstraintsView = new Class(View, {

  init: function (opts) {
    DirectorySearchConstraintsView.superClass.init.apply(this, arguments);
    this.constraints = [];
    this.typeMenus = [];

    // create a view for storing the constraints
    this.constraintsView = document.createElement("div");
    DOM.addClassName(this.constraintsView, "Constraints");
    this.view.appendChild(this.constraintsView);

    // start with empty constraint
    this.addConstraint('Interest', {values: {"int_like": "mac dre"}});
    this.addConstraint();
  },

  renderNewConstraint: function (c) {
    var self = this;

    // get the constraint's rendered self
    var constraintElement = c.render();
    if (! constraintElement) return;
    /////////////////////////////////////

    // create container for this constraint
    var constraintContainer = document.createElement("div");
    DOM.addClassName(constraintContainer, "ConstraintContainer");
    constraintContainer.appendChild(constraintElement);
    ///////////////////////////////////////

    // build the constraint type menu
    var typeMenu = document.createElement("select");
    DirectorySearchConstraintTypes.forEach(function (type) {
      var displayName = DirectorySearchConstraintPrototypes[type] &&
        DirectorySearchConstraintPrototypes[type].displayName ?
        DirectorySearchConstraintPrototypes[type].displayName :
        type;

      var typeOpt = document.createElement("option");
      typeOpt.value = type;
      typeOpt.text = displayName;
      if (type == c.type) {
        typeOpt.selected = true;
      }

      Try.these(
                function () { typeMenu.add(typeOpt, 0);    }, // IE
                function () { typeMenu.add(typeOpt, null); }  // Firefox
                );
    });
    this.typeMenus.push(typeMenu);
    var constraintChangedHandler = c.typeChanged.bindEventListener(c);
    DOM.addEventListener(typeMenu, "change", function (e) {
        constraintChangedHandler(e);
        self.updateTypeMenus();
        return false;
    });
    /////////////////////////////////

    // add/remove buttons
    var removeButton = document.createElement("input");
    removeButton.type = "button";

    var addButton = document.createElement("input");
    addButton.type = "button";

    addButton.value = "+";
    removeButton.value = "-";
    DOM.addEventListener(addButton, "click", self.addConstraintHandler.bindEventListener(self));
    DOM.addEventListener(removeButton, "click", function (evt) {
      if (self.constraints.length <= 1) return false;

      self.constraintsView.removeChild(constraintContainer);
      self.constraints.remove(c);
      self.typeMenus.remove(typeMenu);
      return false;
    });
    var btnContainer = document.createElement("span");
    DOM.addClassName(btnContainer, "ConstraintModifyButtons");
    btnContainer.appendChild(removeButton);
    btnContainer.appendChild(addButton);
    //////////////////////

    constraintContainer.appendChild(typeMenu);
    constraintContainer.appendChild(constraintElement);
    constraintContainer.appendChild(btnContainer);
    this.constraintsView.appendChild(constraintContainer);

    this.updateTypeMenus();
  },

  updateTypeMenus: function () {
      // go through the constraint type menus and disable any constraint
      // types that are unique that already exist
      var self = this;
      this.typeMenus.forEach(function (menu) {
          for (var i = 0; i < menu.length; i++) {
              var ele = menu[i];
              var type = ele.value;

              if (! type) continue;

              if (DirectorySearchConstraintPrototypes[type].unique) {
                  // is there already a constraint with this type?
                  if (self.constraints.filter(function (c) {return c.type == type}).length) {
                      if (! ele.selected || menu.value != type)
                          ele.disabled = true;
                  } else {
                      ele.disabled = false;
                  }
              }
          }
      });
  },

  addConstraintHandler: function (evt) {
    this.addConstraint();
    return false;
  },

  addConstraint: function (type, opts) {
      var c = new DirectorySearchConstraint(type, opts);
      this.constraints.push(c);
      this.renderNewConstraint(c);
      this.updateTypeMenus();
  },

  reset: function () {
    this.constraints.empty();
  },

  constraintsEncoded: function () {
    var ce = [];
    this.constraints.forEach(function (c) {
      var encoded = c.asString();
      if (encoded) ce.push(encoded);
    });
    return ce.join("&");
  },

  validate: function () {
      // validate inputs
      // can't have city search with no state or country
      if (this.constraints.filter(function (c) {return c.type == "City"}).length) {
          var stateConst = this.constraints.filter(function (c) {return c.type == "State"})[0];
          var countryConst = this.constraints.filter(function (c) {return c.type == "Country"})[0];
          if (! stateConst && ! countryConst) {
              this.showError("You must also search by a state or country if searching by city");
              return false;
          }
      }

      var cTypes = {};
      for (var i = 0; i < this.constraints.length; i++) {
          var c = this.constraints[i];
          var type = c.type + "";
          var displayName = c.displayName ? c.displayName.toLowerCase() : c.type.toLowerCase();

          // can't have more than one unique constraint
          if (c.unique) {
              if (type && cTypes[type]) {
                  this.showError("You cannot have more than one " + displayName + " constraint");
                  return false;
              }

              cTypes[type] = true;
          }

          if (type && c.validator) {
              switch (c.validator.toLowerCase()) {
              case "integer":
                  for (var j = 0; j < c.fieldNames.length; j++) {
                      var fieldName = c.fieldNames[j];
                      var val = c.fields[fieldName].value;

                      if (! val) continue;

                      if (val != Number(val)) {
                          this.showError("You must enter a numeric value for searching by " + displayName);
                          return false;
                      }

                      if (val < 0) {
                          this.showError("You cannot enter a negative value for searching by " + displayName);
                          return false;
                      }
                  }
                  break;
              }
          }
      }

      return true;
  },

  showError: function (err) {
      LJ_IPPU.showNote("Error: " + err, this.constraintsView, 5000);
  }

});


// directory search constraint base class
var DirectorySearchConstraint = new Class(Object, {
  init: function (type, opts) {
    type = type ? type : '';
    this.type = type;
    this.fields = {};

    if (opts) {
        this.fieldValues = opts.values ? opts.values : {};
    };

    this.rendered = false;
  },

  render: function () {
    if (this.constraintContainer) {
      this.renderExtraFields();
    } else {
      var constraintContainer = document.createElement("span");
      DOM.addClassName(constraintContainer, "Constraint");
      this.constraintContainer = constraintContainer;

      var extraFields = document.createElement("div");
      DOM.addClassName(extraFields, "ConstraintFields");
      constraintContainer.appendChild(extraFields);
      this.extraFields = extraFields;
      this.renderExtraFields();
    }

    return this.constraintContainer;
  },

  typeChanged: function (evt) {
    var menu = evt.target;
    if (! menu || menu.tagName.toUpperCase() != "SELECT") return false;

    var selIndex = menu.selectedIndex;
    if (selIndex == -1) {
      this.type = null;
    } else {
      this.type = menu.value;
    }

    this.render();

    return false;
  },

  renderExtraFields: function () {
    this.extraFields.innerHTML = "";

    if (! this.type) return;

    this.fields = {};

    // reset this prototype to the base class
    this.override(DirectorySearchConstraint.prototype);

    // override this with the subclass prototype
    this.override(DirectorySearchConstraintPrototypes[this.type]);

    this.extraFields.innerHTML = "";

    if (this.renderFields) {
        this.renderFields(this.extraFields);
    } else {
        // no renderFields method defined, default behavior is to just
        // create a text input
        for (var i = 0; i < this.fieldNames.length; i++) {
            var fieldName = this.fieldNames[i];
            var field = document.createElement("input");
            this.fields[fieldName] = field;
            this.extraFields.appendChild(field);
        }
    }

    this.setFieldDefaultValues();
  },

  setFieldDefaultValues: function () {
      // set default field values if they exist
      if (! this.fieldNames || ! this.fieldValues) return;

      var self = this;
      this.fieldNames.forEach(function (field) {
          if (self.fieldValues[field] && self.fields[field])
              self.fields[field].value = self.fieldValues[field];
      });
  },

  // returns a urlencoded representation of this constraint
  asString: function () {
    var fieldNames = this.fieldNames;
    if (! fieldNames) return "";

    var fields = {};

    var self = this;
    fieldNames.forEach(function (fieldName) {
        fields[fieldName] = self.fields[fieldName].value;
    });

    return HTTPReq.formEncoded(fields);
  },

  // returns a json version of this constraint
  asString: function () {
    var fieldNames = this.fieldNames;
    if (! fieldNames) return "";

    var fields = {};

    var self = this;
    fieldNames.forEach(function (fieldName) {
        fields[fieldName] = self.fields[fieldName].value;
    });

    return HTTPReq.formEncoded(fields);
  },

  displayName: "",
  validator: null,
  fieldNames: [],
  renderFields: null,
  unique: false

});

//////// Constraint classes
var DirectorySearchConstraintTypes = [
                                      "",
                                      "Age",
                                      "Interest",
                                      "UpdateTime",
                                      "Country",
                                      "City",
                                      "State",
                                      "Trusts",
                                      "TrustedBy",
                                      "Watches",
                                      "WatchedBy",
                                      "MemberOf"
];

var DirectorySearchConstraintPrototypes = {
  Age: {
    renderFields: function (content) {
      var lowBound = document.createElement("input");
      lowBound.size = 3;
      lowBound.maxLength = 3;
      var highBound = lowBound.cloneNode(false);

      this.fields.age_min = lowBound;
      this.fields.age_max = highBound;

      var t = _textSpan("between ", " and ", " years old");
      [t[0], lowBound, t[1], highBound, t[2]].forEach(function (ele) {
        content.appendChild(ele);
      });
    },
    fieldNames: ["age_min", "age_max"],
    unique: true,
    validator: "integer"
  },

  Interest: {
      fieldNames: ["int_like"]
  },

  Country: {
      fieldNames: ["loc_cn"],
      unique: true
  },

  City: {
      fieldNames: ["loc_ci"],
      unique: true
  },

  State: {
      fieldNames: ["loc_st"],
      unique: true
  },

  Trusts: {
      fieldNames: ["user_trusts"],
      displayName: "User Trusts"
  },

  TrustedBy: {
      fieldNames: ["user_trusted_by"],
      displayName: "User Trusted By"
  },

  Watches: {
      fieldNames: ["user_watches"],
      displayName: "User Watches"
  },

  WatchedBy: {
      fieldNames: ["user_watched_by"],
      displayName: "User Watched By"
  },

  MemberOf: {
      fieldNames: ["user_is_member"],
      displayName: "User is Member Of"
  },

  UpdateTime: {
    renderFields: function (content) {
      var t = _textSpan("Updated in the last ", " day(s)");
      var days = document.createElement("input");
      this.fields.ut_days = days;

      [t[0], days, t[1]].forEach(function (ele) { content.appendChild(ele) });
    },
    fieldNames: ["ut_days"],
    displayName: "Time last updated",
    unique: true,
    validator: "integer"
  }

};
