/*
 * Copyright (c) 2022, Aquiva Labs LLC. All rights reserved.
 *
 *
 * Redistribution and use in source and binary forms, with or without modification,
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * - Neither the name of the Aquiva Labs LLC nor the names of its contributors
 *     may be used to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **/
/**
 * @group apex/core
 */
public inherited sharing class AqAggregation {

    public enum Operation {
        COUNT, 
        COUNT_DISTINCT, 
        SUM, 
        AVERAGE, 
        MAX, 
        MIN
    }

    private final Operation operation;
    private final String fieldName;
    private final String alias;

    private AqAggregation(Operation operation, Schema.SObjectField fieldToken, String alias) {
        Aq.requireValue('fieldToken', fieldToken);
        this.fieldName = fieldToken.getDescribe().getName();
        this.operation = operation;
        this.alias = alias;
    }

    private AqAggregation(Operation operation) {
        this.operation = operation;
        this.fieldName = '';
        this.alias = '';
    }

    public static AqAggregation count() {
        return new AqAggregation(Operation.COUNT);
    }

    public static AqAggregation sum(Schema.SObjectField fieldToken, String alias) {
        return new AqAggregation(Operation.SUM, fieldToken, alias);
    }

    public static AqAggregation count(Schema.SObjectField fieldToken, String alias) {
        return new AqAggregation(Operation.COUNT, fieldToken, alias);
    }

    public static AqAggregation countDistinct(Schema.SObjectfield fieldToken, String alias) {
        return new AqAggregation(Operation.COUNT_DISTINCT, fieldToken, alias);
    }

    public static AqAggregation average(Schema.SObjectfield fieldToken, String alias) {
        return new AqAggregation(Operation.AVERAGE, fieldToken, alias);
    }

    public static AqAggregation max(Schema.SObjectfield fieldToken, String alias) {
        return new AqAggregation(Operation.MAX, fieldToken, alias);
    }

    public static AqAggregation min(Schema.SObjectfield fieldToken, String alias) {
        return new AqAggregation(Operation.MIN, fieldToken, alias);
    }

    public String getAlias() {
        return this.alias;
    }

    public String getFieldName() {
        return this.fieldName;
    }

    public override String toString() {

        return this.operation.name() + '(' + String.escapeSingleQuotes(fieldName) + ') ' + this.alias;
    }

}