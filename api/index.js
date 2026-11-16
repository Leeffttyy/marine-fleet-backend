// Funcion de Vercel. El codigo real esta en src/serverless.ts; Vercel corre
// `npm run build` antes y este archivo solo carga el resultado compilado.
module.exports = require('../dist/serverless').default;
