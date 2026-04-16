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
            description: 'enforce invoking Apex methods with the right arguments',
            url: docUrl('valid-apex-method-invocation'),
        },
        messages: {
            invalidNumberOfArguments:
                'Invalid apex method invocation. Apex methods only accept a single argument.',
            invalidArgumentType:
                'Invalid apex method invocation. Apex methods expect an object as argument.',
        },
        schema: [],
    },

    create(context) {
        function isApexMethodReference(variable) {
            const [def] = variable.defs;

            return (
                def &&
                def.type === 'ImportBinding' &&
                def.node.type === 'ImportDefaultSpecifier' &&
                def.parent.source.value.match(/^@salesforce\/apex(Continuation)?\/.*/)
            );
        }

        function isInvalidApexArgument(node) {
            const { type } = node;
            return type === 'Literal' || type === 'TemplateLiteral' || type === 'ArrayExpression';
        }

        function validateApexInvocation(node, scope) {
            // Invoking an Apex method with zero arguments is fine.
            if (node.arguments.length === 0) {
                return;
            }

            // Report error when invoking an Apex method with multiple arguments.
            if (node.arguments.length > 1) {
                return context.report({
                    node,
                    messageId: 'invalidNumberOfArguments',
                });
            }

            const [arg] = node.arguments;

            if (isInvalidApexArgument(arg)) {
                // Report an error when the first argument is not a supported type.
                return context.report({
                    node,
                    messageId: 'invalidArgumentType',
                });
            } else if (arg.type === 'Identifier') {
                const argReference = scope.references.find((r) => r.identifier === arg);

                // Ignore unresolved or undefined arguments
                if (!argReference || !argReference.resolved) {
                    return;
                }

                // Report an error when the first argument is bound to a constant identifier initialized
                // with an unsupported type.
                const argVariable = argReference.resolved;
                const [argDefinition] = argVariable.defs;
                if (
                    argDefinition &&
                    argDefinition.type === 'Variable' &&
                    argDefinition.parent.kind === 'const' &&
                    argDefinition.node.init &&
                    isInvalidApexArgument(argDefinition.node.init)
                ) {
                    return context.report({
                        node,
                        messageId: 'invalidArgumentType',
                    });
                }
            }
        }

        return {
            CallExpression(node) {
                const { callee } = node;

                if (callee.type !== 'Identifier') {
                    return;
                }

                // Retrieve the callee reference from the current scope.
                const scope = context.getScope();
                const methodReference = scope.references.find((r) => r.identifier === callee);

                // Ignore the call expression if it can't be resolved from the current scope or if the
                // call expression doesn't reference an Apex method.
                if (
                    !methodReference ||
                    !methodReference.resolved ||
                    !isApexMethodReference(methodReference.resolved)
                ) {
                    return;
                }

                validateApexInvocation(node, scope);
            },
        };
    },
};
