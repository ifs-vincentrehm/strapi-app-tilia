module.exports = ({ env }) => ({
    defaultConnection: 'default',
    connections: {
        default: {
            connector: 'bookshelf',
            settings: {
                client: 'postgres',
                host: env('DB_HOST', '127.0.0.1'),
                port: env.int('DB_PORT', 5432),
                database: env('DATABASE_NAME', 'tilia'),
                username: env('DATABASE_USERNAME', 'postgres'),
                password: env('DATABASE_PASSWORD'),
                ssl: env.bool('DATABASE_SSL', false),
            },
            options: {}
        },
    },
});