# fetch-meta-tags

Fetch the meta tags and title from an URL.
Trades correctness for speed, so very fast, but might be wrong.

```
npm install fast-meta-tags
```

## Usage

``` js
const fastMetaTags = require('fast-meta-tags')

// prints title and an array of tags
console.log(await fastMetaTags('https://www.youtube.com/watch?v=24GfgNtnjXc'))
```

## License

Apache-2.0
