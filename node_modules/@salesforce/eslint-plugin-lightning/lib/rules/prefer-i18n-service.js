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
            description: 'suggest usage of "@salesforce/i18n-service" over "Intl" constructor',
            url: docUrl('prefer-i18n-service'),
        },
    },

    create(context) {
        return {
            NewExpression(node) {
                const { callee } = node;
                const intlFormatMethods = ['DateTimeFormat', 'NumberFormat', 'RelativeTimeFormat'];

                if (
                    callee &&
                    callee.object &&
                    callee.object.name === 'Intl' &&
                    callee.property &&
                    intlFormatMethods.includes(callee.property.name)
                ) {
                    context.report({
                        node,
                        message:
                            'Prefer using "@salesforce/i18n-service" over directly calling "Intl".',
                    });
                }
            },
        };
    },
};
