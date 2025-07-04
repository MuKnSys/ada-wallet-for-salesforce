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
 * @description JSON helpers
 * @group apex/core
 */
public inherited sharing class AqJson {

    //Remove all null properties from JSON
    public static String stripNulls(String inputJson, Boolean pretty) {

        JSONParser parser = JSON.createParser(inputJson);
        JSONGenerator generator = JSON.createGenerator(pretty);

        JSONToken nextToken = parser.nextToken();

        while (nextToken != null) {

            if (nextToken == JSONToken.FIELD_NAME) {

                nextToken = parser.nextToken();
                if (nextToken == JSONToken.VALUE_NULL) {
                    continue;
                } else {
                    generator.writeFieldName(parser.getCurrentName());
                }
            }

            if (nextToken == JSONToken.START_OBJECT) {
                generator.writeStartObject();
            } else if (nextToken == JSONToken.END_OBJECT) {
                generator.writeEndObject();
            } else if (nextToken == JSONToken.START_ARRAY) {
                generator.writeStartArray();
            } else if (nextToken == JSONToken.END_ARRAY) {
                generator.writeEndArray();
            } else if (nextToken == JSONToken.VALUE_TRUE) {
                generator.writeBoolean(true);
            } else if (nextToken == JSONToken.VALUE_FALSE) {
                generator.writeBoolean(false);
            } else if (nextToken == JSONToken.VALUE_STRING) {
                generator.writeString(parser.getText());
            } else if (nextToken == JSONToken.VALUE_NUMBER_INT) {
                generator.writeNumber(parser.getIntegerValue());
            } else if (nextToken == JSONToken.VALUE_NUMBER_FLOAT) {
                generator.writeNumber(parser.getDecimalValue());
            }

            nextToken = parser.nextToken();
        }

        return generator.getAsString();
    }

}
