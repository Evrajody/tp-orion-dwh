<?php
// =============================================================================
//  Index personnalisé Adminer pour TP1 Orion.
//  Pré-remplit la liste déroulante des serveurs disponibles dans la stack :
//    - postgres-oltp  (PostgreSQL — base opérationnelle)
//    - postgres-dwh   (PostgreSQL — entrepôt de données)
//    - mssql-etl      (SQL Server — moteur ETL OrionETL)
//
//  Adminer est monté sur http://localhost:${ADMINER_PORT}.
// =============================================================================

function adminer_object() {

    // ---------------------------------------------------------------
    //  Plugin minimal : présente un <select> de serveurs au login,
    //  forcé sur le bon driver à la connexion.
    // ---------------------------------------------------------------
    class OrionAdminer extends Adminer {

        private $servers = [
            'orion-oltp' => [
                'label'  => 'Orion OLTP — Postgres (orion_oltp)',
                'driver' => 'pgsql',
                'server' => 'postgres-oltp',
                'db'     => 'orion_oltp',
            ],
            'orion-dwh' => [
                'label'  => 'Orion DWH — Postgres (orion_dwh)',
                'driver' => 'pgsql',
                'server' => 'postgres-dwh',
                'db'     => 'orion_dwh',
            ],
            'orion-etl' => [
                'label'  => 'OrionETL — SQL Server',
                'driver' => 'mssql',
                'server' => 'mssql-etl',
                'db'     => 'OrionETL',
            ],
        ];

        function name() {
            return '<a href="." class="h1">Orion — Adminer</a>';
        }

        function loginForm() {
            $current = $_POST['auth']['orion_target'] ?? 'orion-oltp';
            echo "<table class=\"layout\">\n";
            echo "<tr><th>Cible Orion</th><td><select name=\"auth[orion_target]\">";
            foreach ($this->servers as $key => $cfg) {
                $sel = ($key === $current) ? ' selected' : '';
                echo "<option value=\"$key\"$sel>" . htmlspecialchars($cfg['label']) . "</option>";
            }
            echo "</select></td></tr>\n";
            echo "<tr><th>Utilisateur<td><input name=\"auth[username]\" autocomplete=\"username\" autofocus>\n";
            echo "<tr><th>Mot de passe<td><input type=\"password\" name=\"auth[password]\" autocomplete=\"current-password\">\n";
            echo "<tr><th>Base (optionnel)<td><input name=\"auth[db]\" placeholder=\"laissez vide pour la base par défaut\">\n";
            echo "</table>\n";
            echo "<p><input type=\"submit\" value=\"Se connecter\"></p>\n";
            echo "<input type=\"hidden\" name=\"token\" value=\"" . get_token() . "\">\n";
            return true;
        }

        function login($login, $password) {
            // Empêche la connexion si la cible est inconnue
            $target = $_POST['auth']['orion_target'] ?? null;
            if ($target && !isset($this->servers[$target])) {
                return 'Cible Orion inconnue.';
            }
            return true;
        }

        function credentials() {
            $target = $_GET['orion_target'] ?? $_POST['auth']['orion_target'] ?? 'orion-oltp';
            if (!isset($this->servers[$target])) {
                $target = 'orion-oltp';
            }
            $cfg = $this->servers[$target];
            return [$cfg['server'], $_GET['username'] ?? '', $_POST['auth']['password'] ?? ''];
        }

        function database() {
            $target = $_GET['orion_target'] ?? $_POST['auth']['orion_target'] ?? 'orion-oltp';
            if (!empty($_POST['auth']['db'])) return $_POST['auth']['db'];
            return $this->servers[$target]['db'] ?? '';
        }

        function permanentLogin($create = false) {
            // Désactive le « remember me » : sessions courtes pour TP.
            return false;
        }
    }

    return new OrionAdminer();
}

// On expose les paramètres importants en GET pour propagation cross-pages.
if (!empty($_POST['auth']['orion_target'])) {
    $_GET['orion_target'] = $_POST['auth']['orion_target'];
    // Driver imposé selon la cible.
    $map = ['orion-oltp' => 'pgsql', 'orion-dwh' => 'pgsql', 'orion-etl' => 'mssql'];
    $_GET['driver'] = $map[$_POST['auth']['orion_target']] ?? 'pgsql';
}

include "./adminer.php";
