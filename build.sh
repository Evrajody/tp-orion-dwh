#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Pipeline de compilation du rapport :
#   1. Rendu des diagrammes Mermaid (.mmd) en PDF via le conteneur officiel
#      `minlag/mermaid-cli` (pas d installation locale requise).
#   2. Compilation LaTeX avec tectonic.
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build

MMDC_IMAGE="minlag/mermaid-cli:latest"

# Le conteneur tourne sous l user "mermaidcli" (uid 1001). Pour qu il puisse
# ecrire dans build/, on rend ce dossier accessible en ecriture (mode 777
# avec sticky bit), puis on remet des droits normaux apres.
chmod 777 build

# Pull silencieux la première fois
if ! docker image inspect "$MMDC_IMAGE" >/dev/null 2>&1; then
  echo "[mermaid] téléchargement de l'image $MMDC_IMAGE ..."
  docker pull "$MMDC_IMAGE"
fi

shopt -s nullglob
for src in diagrams/*.mmd; do
  name="$(basename "${src%.mmd}")"
  out="build/${name}.pdf"
  echo "[mermaid] $src -> $out"
  docker run --rm \
    -v "$PWD":/data \
    -w /data \
    "$MMDC_IMAGE" \
      -i "$src" \
      -o "$out" \
      -t neutral \
      -b transparent \
      --pdfFit
done
shopt -u nullglob

# On rend la propriete a l user courant (les fichiers ecrits sont uid=1001)
if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
  sudo chown -R "$(id -u):$(id -g)" build 2>/dev/null || true
fi

echo "[tectonic] compilation rapport.tex"
tectonic --keep-logs rapport.tex

echo "[tectonic] compilation uml-poster.tex (UML monopage A0)"
tectonic --keep-logs uml-poster.tex

echo "[tectonic] compilation uml-individual.tex (1 page A3 par diagramme)"
tectonic --keep-logs uml-individual.tex

# --- decoupage en 11 PDF nommes individuellement -----------------------------
if command -v pdfseparate >/dev/null 2>&1; then
  mkdir -p build/uml-individual
  rm -f build/uml-individual/*.pdf
  pdfseparate uml-individual.pdf 'build/uml-individual/_p%d.pdf'
  i=1
  for name in 10-uml-usecase 11-uml-class 12-uml-sequence-order 13-uml-sequence-etl \
              14-uml-activity-order 15-uml-activity-etl 16-uml-state-order \
              17-uml-state-contract 18-uml-component 19-uml-deployment 20-uml-package; do
    mv "build/uml-individual/_p${i}.pdf" "build/uml-individual/${name}.pdf"
    i=$((i+1))
  done
  echo "[split] 11 PDF individuels -> build/uml-individual/"
else
  echo "[split] pdfseparate non installe, etape ignoree (paquet poppler-utils)"
fi

echo
echo "OK -> $(pwd)/rapport.pdf"
echo "OK -> $(pwd)/uml-poster.pdf"
echo "OK -> $(pwd)/build/uml-individual/*.pdf"
