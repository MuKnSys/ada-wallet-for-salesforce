export declare class NoLwcModuleFound extends Error {
    code: string;
    constructor(importee: string, importer: string);
}
export declare class LwcConfigError extends Error {
    scope: string;
    code: string;
    constructor(message: string, { scope }: {
        scope: string;
    });
}
