#!/bin/bash

WEBPACK_CONF="webpack.config.ts"
# Init Project
yarn init -y
clear
# Install dependencies
yarn add -D @babel/core @babel/preset-env @babel/preset-typescript @types/node @types/webpack @types/webpack-node-externals babel-loader ts-loader ts-node typescript webpack webpack-cli webpack-node-externals webpack-shell-plugin-next rimraf nodemon webpack-dev-server @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint eslint-plugin-import eslint-plugin-node eslint-plugin-promise eslint-plugin-standard prettier @types/cors @types/express @types/cookie-parser @tsconfig/recommended tsconfig-paths-webpack-plugin
# removed: eslint-config-standard
clear
yarn add express cors cookie-parser helmet http-terminator dotenv


#----- Webpack Config -----

echo """import path from 'path'
import nodeExternals from 'webpack-node-externals'
import { Configuration } from 'webpack'
import WebpackShellPluginNext from 'webpack-shell-plugin-next'
import TsconfigPathsPlugin from 'tsconfig-paths-webpack-plugin'
const getConfig = (_env: { [key: string]: string }, argv: { [key: string]: string }): Configuration => {
  require('dotenv').config({
    path: path.resolve(__dirname, `.env`)
  })
  return {
    entry: './src/index.ts',
    target: 'node',
    mode: argv.mode === 'production' ? 'production' : 'development',
    externals: [nodeExternals()],
    plugins: [
      new WebpackShellPluginNext({
        onBuildStart: {
          scripts: ['npm run clean:dev && npm run clean:prod'],
          blocking: true,
          parallel: false
        },
        onBuildEnd: {
          scripts: ['npm run dev'],
          blocking: false,
          parallel: true
        }
      })
    ],
    module: {
      rules: [
        {
          test: /\.(ts|js)$/,
          loader: 'ts-loader',
          options: {},
          exclude: /node_modules/
        }
      ]
    },
    resolve: {
      plugins: [new TsconfigPathsPlugin()],
      extensions: ['.ts', '.js'],
      alias: {
        src: path.resolve(__dirname, 'src'),
        libs: path.resolve(__dirname, 'src/libs/*'),
        repos: path.resolve(__dirname, 'src/repos/*'),
        controllers: path.resolve(__dirname, 'src/controllers/*'),
        middlewares: path.resolve(__dirname, 'src/middlewares/*')
      }
    },
    output: {
      path: path.join(__dirname, 'build'),
      filename: 'index.js'
    },
    optimization: {
      moduleIds: 'deterministic',
      splitChunks: {
        chunks: 'all'
      }
    }
  }
}
export default getConfig
""" >> $WEBPACK_CONF

mkdir src src/controllers src/repos src/middlewares src/middlewares/auth src/libs src/routes src/www

#
# ---------- CONFIGS ----------
#

# TYPESCRIPT SETUP
echo '''{
  "extends": "@tsconfig/recommended/tsconfig.json",
  "compilerOptions": {
    "target": "es6",
    "module": "commonjs",
    "moduleResolution": "node",
    "allowSyntheticDefaultImports": true,
    "allowJs": true,
    "importHelpers": true,
    "jsx": "react",
    "alwaysStrict": true,
    "sourceMap": true,
    "forceConsistentCasingInFileNames": true,
    "noFallthroughCasesInSwitch": true,
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitAny": false,
    "noImplicitThis": false,
    "strictNullChecks": false,
    "outDir": "./build",
    "baseUrl": "./",
    "paths": {
      "@src/*": ["src/*"],
      "@libs/*": ["src/libs/*"],
      "@repos/*": ["src/repos/*"],
      "@controllers/*": ["src/controllers/*"],
      "@middlewares/*": ["src/middlewares/*"]
    }
  },
  "include": ["src/**/*", "__tests__/**/*"],
  "exclude": ["node_modules", "build"]
}''' >> tsconfig.json
# PRETTIER SETUP
echo '''{
  "singleQuote": true,
  "arrowParens": "always",
  "printWidth": 120,
  "trailingComma": "none",
  "semi": false
}''' >> .prettierrc.json
echo '''/build
/dist''' >> .prettierignore

# CORS
echo """import cors from 'cors';
export const allowedOrigins = [
	'http://localhost:3000',
	'http://localhost:3001',
];
const corsOptions: cors.CorsOptions = {
	origin: function (origin: any, callback: Function) {
		// Allow request with no origins (like mobile apps or curl requests)
		if (allowedOrigins.indexOf(origin) !== -1 || !origin) {
			callback(null, true);
		} else {
			callback(new Error('cors'));
		}
	},
	allowedHeaders: [
		'Origin',
		'X-Requested-With',
		'Content-Type',
		'Accept',
		'X-Access-Token',
		'Authorization',
	],
	methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
	credentials: true,
	optionsSuccessStatus: 200,
};
export default corsOptions;""" >> src/libs/cors.ts
# SERVICE BREAKER
echo '''import { exit } from "process";
import server, { httpTerminator } from "src/app";
class ServiceBreaker {
  public async handleExit(code: number, timeout = 5000): Promise<void> {
    try {
      console.log(`Attempting a graceful shutdown with code ${code}`);

      setTimeout(() => {
        console.log(`Forcing a shutdown with code ${code}`);
        exit(code);
      }, timeout).unref();

      if (server.listening) {
        console.log("Terminating HTTP connections");
        await httpTerminator.terminate();
      }

      console.log(`Exiting gracefully with code ${code}`);
      exit(code);
    } catch (error) {
      console.log("Error shutting down gracefully");
      console.log(error);
      console.log(`Forcing exit with code ${code}`);
      exit(code);
    }
  }
}
export default new ServiceBreaker();
''' >> src/libs/service-breaker.ts
# PROCESS
echo '''import serviceBreaker from "libs/service-breaker";
process.on("unhandledRejection", (reason: Error | any) => {
	console.log(`Unhandled Rejection: ${reason.message || reason}`);
	throw new Error(reason.message || reason);
});
process.on("uncaughtException", (error: Error) => {
	console.log(`Uncaught Exception: ${error.message}`);
});
process.on("SIGTERM", () => {
	console.log(`Process ${process.pid} received SIGTERM: Exiting with code 0`);
	serviceBreaker.handleExit(0);
});
process.on("SIGINT", () => {
	console.log(`Process ${process.pid} received SIGINT: Exiting with code 0`);
	serviceBreaker.handleExit(0);
});''' >> src/process.ts
# APP
echo """import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import cors from 'cors';
import express, { Application, urlencoded, json, Request, Response, NextFunction } from 'express';
import { createHttpTerminator } from 'http-terminator';
import { createServer, Server } from 'http';
import corsOptions from 'libs/cors';

const app: Application = express();
const server: Server = createServer(app);
export const httpTerminator = createHttpTerminator({ server });

// Features
app.enable('trust proxy');

// Core Middlewares
app.use(cors(corsOptions));
app.use(helmet());
app.use(cookieParser());
app.use(urlencoded({ extended: true, limit: '100kb' }));
app.use(json({ limit: '10kb', type: 'application/json' }));

// global middlewares

// ADMIN API POINTS

// USER API POINTS
app.get('/', (req: Request, res: Response) => {
  res.send('All Ok')
});

// ERROR POINTS
app.use((_req: Request, res: Response) => {
	return res.status(404).send('Not found!');
});
// response api errors
app.use((err: Error, _req: Request, res: Response, next: NextFunction) => {
	if (process.env.NODE_ENV !== 'production')
		console.log('Error encountered:', err.message || err);
	if (err?.message === 'cors') return res.end('Not allowed by CORS');
	next(err);
});
app.use((err: Error, req: Request, res: Response) => {
	// Your error handler ...
});

export default server;""" >> src/app.ts
# ENTRY
echo '''import "src/process";
import * as dotenv from "dotenv";
import server from "src/app";
dotenv.config();

server.listen(process.env.PORT, () => {
	if (process.env.NODE_ENV !== "production")
		console.log(`${process.env.NODE_ENV} server running...`);
});''' >> src/index.ts
# HOC
echo """import { RequestHandler,Request, NextFunction, Response, } from 'express';
export const useAsync = (fn: RequestHandler) => (req: Request, res: Response, next: NextFunction) => Promise.resolve(fn(req, res, next)).catch(next);""" >> src/libs/index.ts



echo '''# APP CONFIG
#APP_NAME=name
#APP_URI=name.com
PORT=8000
#TZ=Asia/Dhaka

# DATABASE CONFIG

#----POSTGRESQL----
DB_HOST=localhost
DB_PORT=5432
DB_USER=username
DB_PASS=password
DB_NAME=database
DB_MXCON=20

#----REDIS----
REDIS_URI=redis://127.0.0.1:6379


#----MAIL----
MAIL_USER=something@gmail.com
MAIL_PASS=password

# JWT CONFIG
JWT_ISSUER=app_provider_name
JWT_SUBJECT=anonymouse@anon.com
JWT_AUDIENCE=https://localhost:8000
JWT_ACCESS_TOKEN_EXP=10
JWT_REFRESH_TOKEN_EXP=3''' >> .env

# Create client tool
echo '''@baseUrl = http://localhost:8000
### LOGIN
POST {{baseUrl}}/login
Content-Type: application/json

{
    "username":"demouser",
    "password":"demopass123"
}

### AUTH
GET {{baseUrl}}/
Content-Type: application/json
Authorization: bearer {{accessToken}}''' >> src/www/client.http

clear
npx eslint --init
clear

echo ''' Copy below code and save inside package.json
"scripts": {
    "serve": "webpack --watch --env mode=development --config webpack.config.ts",
    "clean:dev": "rimraf build",
    "clean:prod": "rimraf dist",
    "build": "webpack --mode production --config webpack.config.ts",
    "dev": "nodemon build/index.js --watch build",
    "prod": "nodemon dist/index.js --watch dist",
    "test": "echo \"Error: no test specified\" && exit 1"
},
'''