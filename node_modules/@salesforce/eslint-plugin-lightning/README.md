# @salesforce/eslint-plugin-lightning

> Collection of ESLint rules for Salesforce Lightning platform.

## Installation

```sh
$ npm install eslint @salesforce/eslint-plugin-lightning --save-dev
```

## Usage

Add this plugin to your ESLint configuration and extend your desired configuration. See [ESLint documentation](http://eslint.org/docs/user-guide/configuring#configuring-plugins) for details.

```json
{
    "plugin": ["@salesforce/eslint-plugin-lightning"],
    "rules": {
        "@salesforce/lightning/no-moment": "error",
        "@salesforce/lightning/prefer-i18n-service": "error"
    }
}
```

## Rules

### Internationalization rules

| Rule ID                                                                                | Description                                                             | Fixable |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ------- |
| [lightning/no-aura-localization-service](./docs/rules/no-aura-localization-service.md) | prevent usage of `$A.localizationService`                               |         |
| [lightning/no-moment](./docs/rules/no-moment.md)                                       | prevent usage of `moment` library                                       |         |
| [lightning/prefer-i18n-service](./docs/rules/prefer-i18n-service.md)                   | suggest usage of `@salesforce/i18n-service` over direct calls to `Intl` |         |

### Apex rules

| Rule ID                                                                                | Description                                            | Fixable |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------ | ------- |
| [lightning/valid-apex-method-invocation](./docs/rules/valid-apex-method-invocation.md) | enforce invoking Apex methods with the right arguments |         |
