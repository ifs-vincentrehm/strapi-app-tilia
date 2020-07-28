'use strict';

const slugify = require('slugify');

/**
 * Read the documentation (https://strapi.io/documentation/v3.x/concepts/models.html#lifecycle-hooks)
 * to customize this model
 */

module.exports = {
    lifecycles: {
        async beforeCreate(data) {
          if (data.title) {
            data.slug = slugify(data.title, {lower: true});
          }

          if (data.published_at) {
            data.published_at = new Date();
          }
        },
        async beforeUpdate(params, data) {
          if (data.title) {
            data.slug = slugify(data.title, {lower: true});
          }

          if (data.published_at === null) {
            data.published_at = new Date();
          }
        },
      }
};
