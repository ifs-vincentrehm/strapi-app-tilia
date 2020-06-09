'use strict';

const slugify = require('slugify');

module.exports = {
    lifecycles: {
        beforeCreate: async model => {
            if (model.title) {
                model.slug = slugify(model.title).toLowerCase();
            }

            if (model.published_at) {
                console.log('create', model)
                model.published_at = new Date();
            }
        },
        beforeUpdate: async(params, model) => {
            model.slug = slugify(model.title).toLowerCase();
            if (model.published_at === null) {
                console.log("update", model)
                model.published_at = new Date();
            }
        }
    }
};