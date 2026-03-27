/*
 * Copyright (c) 2021, salesforce.com, inc.
 * All rights reserved.
 * SPDX-License-Identifier: MIT
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/MIT
 */
'use strict';

const { docUrl } = require('../utils/doc-url');

module.exports = {
    meta: {
        docs: {
            description: 'disallow usage of "$A.localizationService"',
            url: docUrl('no-aura-localization-service'),
        },
    },

    create(context) {
        return {
            MemberExpression(node) {
                if (
                    node &&
                    node.object &&
                    ((node.object.type === 'Identifier' && node.object.name === '$A') ||
                        (node.object.type === 'MemberExpression' &&
                            node.object.property &&
                            node.object.property.name === '$A')) &&
                    node.property &&
                    node.property.name === 'localizationService'
                ) {
                    context.report({
                        node,
                        message: 'Disallow usage of "$A.localizationService".',
                    });
                }
            },
        };
    },
};
