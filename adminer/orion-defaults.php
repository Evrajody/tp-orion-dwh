<?php
// =============================================================================
//  Plugin Adminer — pré-remplit pilote / utilisateur / base depuis l'environnement
//  Le serveur est déjà pris en charge par le plugin par défaut de l'image
//  (ADMINER_DEFAULT_SERVER). On ajoute ici :
//    - ADMINER_DEFAULT_DRIVER   (ex: pgsql, mssql)
//    - ADMINER_DEFAULT_USERNAME
//    - ADMINER_DEFAULT_DB
//  Le mot de passe reste à saisir manuellement (et c'est très bien comme ça).
// =============================================================================

return new class extends \Adminer\Plugin {
    public function loginFormField(string $name, string $heading, string $field): string
    {
        $driver = $_ENV['ADMINER_DEFAULT_DRIVER']   ?? getenv('ADMINER_DEFAULT_DRIVER')   ?: '';
        $user   = $_ENV['ADMINER_DEFAULT_USERNAME'] ?? getenv('ADMINER_DEFAULT_USERNAME') ?: '';
        $db     = $_ENV['ADMINER_DEFAULT_DB']       ?? getenv('ADMINER_DEFAULT_DB')       ?: '';

        switch ($name) {
            case 'driver':
                if ($driver !== '') {
                    $field = preg_replace('/(<option[^>]*) selected/', '$1', $field);
                    return preg_replace(
                        '/(<option value="' . preg_quote($driver, '/') . '")/',
                        '$1 selected',
                        $field,
                        1
                    );
                }
                break;

            case 'username':
                if ($user !== '') {
                    return preg_replace(
                        '/(name="auth\[username\]"[^>]*?)value=""/',
                        '$1value="' . htmlspecialchars($user, ENT_QUOTES) . '"',
                        $field,
                        1
                    );
                }
                break;

            case 'db':
                if ($db !== '') {
                    return preg_replace(
                        '/(name="auth\[db\]"[^>]*?)value=""/',
                        '$1value="' . htmlspecialchars($db, ENT_QUOTES) . '"',
                        $field,
                        1
                    );
                }
                break;
        }

        return $field;
    }
};
