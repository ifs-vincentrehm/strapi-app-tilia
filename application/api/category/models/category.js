'use strict';

const slugify = require('slugify');

module.exports = {
    lifecycles: {
        beforeCreate: async model => {
            if (model.name) {
                model.slug = slugify(model.name).toLowerCase();
            }
        },
        beforeUpdate: async(params, model) => {
            model.slug = slugify(model.name).toLowerCase();
        }
    }
};