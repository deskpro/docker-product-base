<?php

class DeskproSimulateRelease
{
    public static function runWeb(): void
    {
        $inst = new static();
        $inst->web();
    }

    public static function runCli(string $project): void
    {
        $inst = new static();
        match ($project) {
            'fixtures' => $inst->fixturesCli($_SERVER['argv']),
            'install' => $inst->fixturesCli(['artisan', 'install']),
            'migrations' => $inst->migrationsCli($_SERVER['argv']),
        };
    }

    private function needsInstall(): bool
    {
        return file_exists('/run/sim/needs-installer');
    }

    private function needsMigrations(): bool
    {
        return file_exists('/run/sim/needs-migrations');
    }

    ###################################################################
    # WEB
    ###################################################################

    public function web(): void
    {
        match ($_SERVER['REQUEST_URI'] ?? '/') {
            '/' => printf("Simulating source files\n"),
            '/phpinfo' => phpinfo(INFO_GENERAL | INFO_CONFIGURATION | INFO_MODULES | INFO_ENVIRONMENT | INFO_VARIABLES),
            '/api/v2/helpdesk/discover' => $this->simDiscoverEndpoint(),
            '/dump-config' => $this->webDumpConfig(),
            default => http_response_code(404),
        };
    }

    private function sendJson(string $json, int $httpStatus = 200): void
    {
        http_response_code($httpStatus);
        header('Content-Type: application/json; charset=utf-8');
        echo $json;
    }

    private function sendText(string $text, int $httpStatus = 200): void
    {
        http_response_code($httpStatus);
        header('Content-Type: text/plain; charset=utf-8');
        echo $text;
    }

    private function webDumpConfig(): void
    {
        $CONFIG = [];
        require('/srv/deskpro/INSTANCE_DATA/config.php');
        $this->sendJson(json_encode($CONFIG, JSON_PRETTY_PRINT | JSON_PARTIAL_OUTPUT_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    private function simDiscoverEndpoint(): void
    {
        if ($this->needsInstall()) {
            $this->sendText('DB needs install', 500);
            return;
        } else if ($this->needsMigrations()) {
            $this->sendText('DB needs migrations', 423);
            return;
        }

        $this->sendJson(<<<EOT
        {
            "data": {
                "helpdesk_uuid": "20DC3C26-4AAB-41CB-817F-F28B18BEE88C",
                "is_deskpro": true,
                "is_cloud": false,
                "helpdesk_url": "https:\/\/deskpro.test\/",
                "base_api_url": "https:\/\/deskpro.test\/api\/v2\/",
                "build": "0",
                "build_id": 0,
                "build_name": "0",
                "version": "0",
                "requirements": {
                    "schema": "^1.0",
                    "containerApi": "1.0.0"
                },
                "build_info": {
                    "id": "0",
                    "time": 599443200,
                    "coreVersion": "0.0.0",
                    "prereleaseTag": "dev",
                    "schemaVersion": "1.0.0"
                }
            },
            "meta": {},
            "linked": {}
        }
EOT);
    }

    ###################################################################
    # FIXTURES CLI
    ###################################################################

    public function fixturesCli(array $argv): void
    {
        match ($argv[1] ?? '') {
            'test:wait-db' => $this->simCliTestDbWait(),
            'install' => $this->simCliInstall(),
            default => $this->cliExit(1, "Unknown command: " . implode(' ', $argv)),
        };
    }

    private function simCliTestDbWait(): void
    {
        echo "Simulating command: test:wait-db\n";
        $this->cliWait('SIM_WAITDB_WAIT');
        $this->cliExit(0, 'DB is ready');
    }

    private function simCliInstall(): void
    {
        echo "Simulating command: install\n";
        $this->cliWait('SIM_INSTALL_WAIT', 3);
        $this->cliExit(0, 'DB is ready');
    }

    ###################################################################
    # MIGRATIONS CLI
    ###################################################################

    public function migrationsCli(array $argv): void
    {
        match ($argv[1] ?? '') {
            'migrations:status' => $this->simCliMigrationStatus(),
            'migrations:exec' => $this->simCliMigrationsExec(),
            default => $this->cliExit(1, "Unknown command: " . implode(' ', $argv)),
        };
    }

    private function simCliMigrationStatus(): void
    {
        echo "Simulating command: migrations:status\n";

        if ($this->needsInstall()) {
            $this->cliExit(2 /*StatusCommand::EXIT_EMPTY_DB*/, 'DB needs install');
        } else if ($this->needsMigrations()) {
            $this->cliExit(10 /*StatusCommand::EXIT_PENDING_MIGRATIONS*/, 'DB needs migrations');
        }

        $this->cliExit(0, 'No migrations needed');
    }

    private function simCliMigrationsExec(): void
    {
        echo "Simulating command: migrations:exec\n";

        $this->cliWait('SIM_MIGRATION_WAIT', 3);
        $this->cliExit(0, 'Done');
    }

    ###################################################################
    # CLI Utils
    ###################################################################

    private function cliExit(int $code = 0, ?string $message = null): void
    {
        if ($message) {
            printf("exit:%d %s\n", $code, $message);
        }

        exit($code);
    }

    private function cliWait(string $envVarName, int $default = 0): void
    {
        $secs = getenv($envVarName) ?: $default;
        if (!$secs) {
            return;
        }

        printf("Sleeping for %d seconds (%s)\n", $secs, $envVarName);
        sleep($secs);
    }
}
