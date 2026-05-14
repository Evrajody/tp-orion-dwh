#!/usr/bin/env python3
"""
Generateur du package SSIS Orion_Pipeline_Quotidien.dtsx.

Strategie validee :
- Aucune Connection Manager au niveau package : on suppose 3 CMs project-level
  existants (ORIONOLTP.orion, ORIONETL.orion, ORIONDWH.orion) que tu cree
  manuellement dans le projet SSDT avant d'importer ce .dtsx.
- Toutes les DFT sont des coquilles vides (<pipeline version="1"/>). Tu
  ajoutes Source ODBC + Destination OLE DB a la souris dans chaque DFT
  (~5 min par DFT, SSDT remplit les metadonnees colonnes contre les bases
  reelles).
- Les Execute SQL Tasks ont leur SqlStatementSource mais pas leur Connection
  liee : tu cliques chaque task, tu choisis ta CM dans la liste deroulante,
  tu sauvegardes (4 clics au total).
- Squelette : Sequence Containers + precedences toutes en place
  (TRUNCATE -> DFT, fan-in -> Lignes_Commande / FaitVentes, etc).

Sortie : ssis/Orion_Pipeline_Quotidien.dtsx
"""

from __future__ import annotations

import datetime as _dt
import os
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(HERE, "Orion_Pipeline_Quotidien.dtsx")

# uuid5 sur namespace fixe = GUIDs reproductibles (regeneration idempotente).
_NS = uuid.UUID("11111111-1111-1111-1111-111111111111")

def guid(*parts: str) -> str:
    return "{" + str(uuid.uuid5(_NS, "/".join(parts))).upper() + "}"


def xml_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
         .replace("<", "&lt;")
         .replace(">", "&gt;")
         .replace('"', "&quot;")
    )


def _ssis_datetime(d: _dt.datetime) -> str:
    """Format M/d/yyyy h:mm:ss AM/PM (le seul que CPackage::LoadFromXML accepte)."""
    ampm = "PM" if d.hour >= 12 else "AM"
    hour_12 = d.hour % 12 or 12
    return f"{d.month}/{d.day}/{d.year} {hour_12}:{d.minute:02d}:{d.second:02d} {ampm}"


# ============================================================================
# Definitions
# ============================================================================

# 7 staging DFTs avec leur TRUNCATE prealable.
STAGING_DFTS = [
    ("DFT_Staging_Geographie",      "TRUNCATE TABLE staging.geographie_full;"),
    ("DFT_Staging_Fournisseur",     "TRUNCATE TABLE staging.fournisseur_full;"),
    ("DFT_Staging_Canal",           "TRUNCATE TABLE staging.canal;"),
    ("DFT_Staging_Produit",         "TRUNCATE TABLE staging.produit_full;"),
    ("DFT_Staging_Client",          "TRUNCATE TABLE staging.client_full;"),
    ("DFT_Staging_Employe",         "TRUNCATE TABLE staging.employe_full;"),
    ("DFT_Staging_Lignes_Commande", "TRUNCATE TABLE staging.lignes_commande;"),
]
# Le dernier (Lignes_Commande) attend la convergence des 6 autres (Logical AND).
STAGING_DIMS = [name for name, _ in STAGING_DFTS[:6]]
STAGING_LAST = STAGING_DFTS[6][0]

# 8 DFT DWH avec leur TRUNCATE prealable.
# Ordre : la fact doit etre tronquee AVANT les dim (FK).
DWH_DFTS = [
    ("DFT_DWH_DimDate",        "TRUNCATE TABLE dw.dim_date;"),
    ("DFT_DWH_DimCanal",       "TRUNCATE TABLE dw.dim_canal;"),
    ("DFT_DWH_DimGeographie",  "TRUNCATE TABLE dw.dim_geographie;"),
    ("DFT_DWH_DimFournisseur", "TRUNCATE TABLE dw.dim_fournisseur;"),
    ("DFT_DWH_DimProduit",     "TRUNCATE TABLE dw.dim_produit;"),
    ("DFT_DWH_DimClient",      "TRUNCATE TABLE dw.dim_client;"),
    ("DFT_DWH_DimEmploye",     "TRUNCATE TABLE dw.dim_employe;"),
    ("DFT_DWH_FaitVentes",     "TRUNCATE TABLE dw.fait_ventes;"),
]
DWH_DIMS = [name for name, _ in DWH_DFTS[:7]]
DWH_LAST = DWH_DFTS[7][0]

# SQL pour les tasks transverses (non lies a un DFT specifique)
SQL_LIRE_WATERMARK = (
    "SELECT ISNULL(MAX(last_value), '1900-01-01') "
    "FROM etl.watermark WHERE job_name = 'fait_ventes';"
)
SQL_EXEC_SP_RUN_PIPELINE = "EXEC etl.sp_run_pipeline;"

# CreatorComputerName / CreatorName : neutres
CREATOR_COMPUTER = "ORION-DEV"
CREATOR_USER     = "ORION-DEV\\orion"

# Contact strings exactement comme dans le sample qui marche
TASK_CONTACT_SQL = (
    "Execute SQL Task; Microsoft Corporation; SQL Server; "
    "(C) Microsoft Corporation; All Rights Reserved;"
    "http://www.microsoft.com/sql/support/default.asp;1"
)
TASK_CONTACT_PIPELINE = (
    "Performs high-performance data extraction, transformation and loading;"
    "Microsoft Corporation; Microsoft SQL Server; "
    "(C) Microsoft Corporation; All Rights Reserved;"
    "http://www.microsoft.com/sql/support/default.asp;1"
)


# ============================================================================
# Generateurs XML
# ============================================================================

def variables_xml() -> str:
    """Variables niveau package, format conforme au sample."""
    return f'''  <DTS:Variables>
    <DTS:Variable
      DTS:CreationName=""
      DTS:DTSID="{guid("var", "ConnString")}"
      DTS:IncludeInDebugDump="2345"
      DTS:Namespace="User"
      DTS:ObjectName="ConnString">
      <DTS:VariableValue
        DTS:DataType="8"
        xml:space="preserve"></DTS:VariableValue>
    </DTS:Variable>
    <DTS:Variable
      DTS:CreationName=""
      DTS:DTSID="{guid("var", "LignesIn")}"
      DTS:IncludeInDebugDump="6789"
      DTS:Namespace="User"
      DTS:ObjectName="LignesIn">
      <DTS:VariableValue
        DTS:DataType="3">0</DTS:VariableValue>
    </DTS:Variable>
    <DTS:Variable
      DTS:CreationName=""
      DTS:DTSID="{guid("var", "LignesOut")}"
      DTS:IncludeInDebugDump="6789"
      DTS:Namespace="User"
      DTS:ObjectName="LignesOut">
      <DTS:VariableValue
        DTS:DataType="3">0</DTS:VariableValue>
    </DTS:Variable>
    <DTS:Variable
      DTS:CreationName=""
      DTS:DTSID="{guid("var", "Watermark")}"
      DTS:IncludeInDebugDump="6789"
      DTS:Namespace="User"
      DTS:ObjectName="Watermark">
      <DTS:VariableValue
        DTS:DataType="7">1/1/1900 12:00:00 AM</DTS:VariableValue>
    </DTS:Variable>
  </DTS:Variables>'''


def sql_task_xml(parent_ref: str, name: str, description: str,
                 sql: str, thread_hint: int,
                 result_set: str | None = None,
                 result_var: str | None = None,
                 indent: int = 8) -> str:
    """Execute SQL Task. result_set in {None, 'ResultSetType_SingleRow'}."""
    ref_id = f"{parent_ref}\\{name}"
    pad = " " * indent

    if result_set:
        result_attr = f'\n              SQLTask:ResultType="{result_set}"'
        bindings = ''
        if result_var:
            bindings = f'''
              <SQLTask:ResultBinding
                SQLTask:ResultName="ResultName0"
                SQLTask:DtsVariableName="{result_var}" />'''
        sql_task_data = f'''<SQLTask:SqlTaskData
              SQLTask:SqlStatementSource="{xml_escape(sql)}"{result_attr}
              xmlns:SQLTask="www.microsoft.com/sqlserver/dts/tasks/sqltask">{bindings}
            </SQLTask:SqlTaskData>'''
    else:
        sql_task_data = (
            f'<SQLTask:SqlTaskData\n'
            f'              SQLTask:SqlStatementSource="{xml_escape(sql)}"\n'
            f'              xmlns:SQLTask="www.microsoft.com/sqlserver/dts/tasks/sqltask" />'
        )

    return f'''{pad}<DTS:Executable
{pad}  DTS:refId="{ref_id}"
{pad}  DTS:CreationName="Microsoft.ExecuteSQLTask"
{pad}  DTS:Description="{xml_escape(description)}"
{pad}  DTS:DTSID="{guid("sql", ref_id)}"
{pad}  DTS:ExecutableType="Microsoft.ExecuteSQLTask"
{pad}  DTS:LocaleID="-1"
{pad}  DTS:ObjectName="{name}"
{pad}  DTS:TaskContact="{TASK_CONTACT_SQL}"
{pad}  DTS:ThreadHint="{thread_hint}">
{pad}  <DTS:Variables />
{pad}  <DTS:ObjectData>
{pad}    {sql_task_data}
{pad}  </DTS:ObjectData>
{pad}</DTS:Executable>'''


def dft_empty_xml(parent_ref: str, name: str, indent: int = 8) -> str:
    """DFT vide -- <pipeline version='1'/>. L'utilisateur remplit le contenu
    a la souris dans SSDT (Source ODBC + Destination OLE DB + Mappages)."""
    ref_id = f"{parent_ref}\\{name}"
    pad = " " * indent
    return f'''{pad}<DTS:Executable
{pad}  DTS:refId="{ref_id}"
{pad}  DTS:CreationName="Microsoft.Pipeline"
{pad}  DTS:Description="Tâche de flux de données"
{pad}  DTS:DTSID="{guid("dft", ref_id)}"
{pad}  DTS:ExecutableType="Microsoft.Pipeline"
{pad}  DTS:LocaleID="-1"
{pad}  DTS:ObjectName="{name}"
{pad}  DTS:TaskContact="{TASK_CONTACT_PIPELINE}">
{pad}  <DTS:Variables />
{pad}  <DTS:ObjectData>
{pad}    <pipeline
{pad}      version="1" />
{pad}  </DTS:ObjectData>
{pad}</DTS:Executable>'''


def precedence_xml(parent_ref: str, from_name: str, to_name: str,
                   pc_name: str | None = None,
                   logical_and: bool = True,
                   value: int = 0,
                   indent: int = 10) -> str:
    """Precedence Constraint a placer dans la <DTS:PrecedenceConstraints>
    d'un conteneur. value=0 Success, 1 Failure, 2 Completion."""
    if pc_name is None:
        pc_name = f"PC_{from_name}_to_{to_name}"
    pad = " " * indent
    pc_ref = f"{parent_ref}.PrecedenceConstraints[{pc_name}]"
    return f'''{pad}<DTS:PrecedenceConstraint
{pad}  DTS:refId="{pc_ref}"
{pad}  DTS:CreationName=""
{pad}  DTS:DTSID="{guid("pc", parent_ref, from_name, to_name)}"
{pad}  DTS:From="{parent_ref}\\{from_name}"
{pad}  DTS:LogicalAnd="{'True' if logical_and else 'False'}"
{pad}  DTS:ObjectName="{pc_name}"
{pad}  DTS:To="{parent_ref}\\{to_name}"
{pad}  DTS:Value="{value}" />'''


# ============================================================================
# Assemblage des Sequence Containers
# ============================================================================

def build_seq_chargement_staging() -> str:
    """SEQ_Chargement_Staging : 7 Truncates + 7 DFT + precedences."""
    parent = "Package\\SEQ_Pipeline_Complet\\SEQ_Chargement_Staging"

    executables = []
    precedences = []

    # Truncates + DFTs (1 truncate par DFT, dans l'ordre)
    thread = 1
    for dft_name, sql_truncate in STAGING_DFTS:
        trunc_name = f"Truncate_{dft_name.replace('DFT_Staging_', '')}"
        executables.append(sql_task_xml(parent, trunc_name,
                                       f"Vide la table staging avant {dft_name}",
                                       sql_truncate, thread_hint=thread,
                                       indent=10))
        thread += 1
        executables.append(dft_empty_xml(parent, dft_name, indent=10))

        # Precedence : chaque truncate -> son DFT
        precedences.append(precedence_xml(parent, trunc_name, dft_name,
                                          pc_name=f"PC_{trunc_name}",
                                          indent=10))

    # Convergence Logical AND : les 6 dimensions -> DFT_Staging_Lignes_Commande
    # (en plus de Truncate_Lignes_Commande -> DFT_Staging_Lignes_Commande
    #  qui existe deja). On ajoute les 6 fan-ins.
    for dim in STAGING_DIMS:
        precedences.append(precedence_xml(parent, dim, STAGING_LAST,
                                          pc_name=f"PC_{dim}_to_{STAGING_LAST}",
                                          logical_and=True, indent=10))

    return f'''        <DTS:Executable
          DTS:refId="{parent}"
          DTS:CreationName="STOCK:SEQUENCE"
          DTS:Description="Conteneur de séquences"
          DTS:DTSID="{guid("seq", parent)}"
          DTS:ExecutableType="STOCK:SEQUENCE"
          DTS:LocaleID="-1"
          DTS:ObjectName="SEQ_Chargement_Staging">
          <DTS:Variables />
          <DTS:Executables>
{chr(10).join(executables)}
          </DTS:Executables>
          <DTS:PrecedenceConstraints>
{chr(10).join(precedences)}
          </DTS:PrecedenceConstraints>
        </DTS:Executable>'''


def build_seq_push_dwh() -> str:
    """SEQ_Push_DWH : 8 Truncates + 8 DFT + precedences vers FaitVentes."""
    parent = "Package\\SEQ_Pipeline_Complet\\SEQ_Push_DWH"

    executables = []
    precedences = []

    thread = 1
    for dft_name, sql_truncate in DWH_DFTS:
        trunc_name = f"Truncate_{dft_name.replace('DFT_DWH_', '')}_DWH"
        executables.append(sql_task_xml(parent, trunc_name,
                                       f"Vide la table DWH avant {dft_name}",
                                       sql_truncate, thread_hint=thread,
                                       indent=10))
        thread += 1
        executables.append(dft_empty_xml(parent, dft_name, indent=10))

        precedences.append(precedence_xml(parent, trunc_name, dft_name,
                                          pc_name=f"PC_{trunc_name}",
                                          indent=10))

    # Convergence Logical AND : les 7 dim -> DFT_DWH_FaitVentes
    for dim in DWH_DIMS:
        precedences.append(precedence_xml(parent, dim, DWH_LAST,
                                          pc_name=f"PC_{dim}_to_{DWH_LAST}",
                                          logical_and=True, indent=10))

    return f'''        <DTS:Executable
          DTS:refId="{parent}"
          DTS:CreationName="STOCK:SEQUENCE"
          DTS:Description="Conteneur de séquences"
          DTS:DTSID="{guid("seq", parent)}"
          DTS:ExecutableType="STOCK:SEQUENCE"
          DTS:LocaleID="-1"
          DTS:ObjectName="SEQ_Push_DWH">
          <DTS:Variables />
          <DTS:Executables>
{chr(10).join(executables)}
          </DTS:Executables>
          <DTS:PrecedenceConstraints>
{chr(10).join(precedences)}
          </DTS:PrecedenceConstraints>
        </DTS:Executable>'''


def build_seq_pipeline_complet() -> str:
    """SEQ_Pipeline_Complet : SQL_Lire_Watermark + Chargement + sp + Push."""
    parent = "Package\\SEQ_Pipeline_Complet"

    sql_lire = sql_task_xml(
        parent, "SQL_Lire_Watermark",
        "Lit le watermark courant depuis OrionETL.etl.watermark",
        SQL_LIRE_WATERMARK, thread_hint=1,
        result_set="ResultSetType_SingleRow",
        result_var="User::Watermark",
        indent=8,
    )
    sql_exec = sql_task_xml(
        parent, "SQL_Exec_sp_run_pipeline",
        "Execute etl.sp_run_pipeline (transformations T-SQL)",
        SQL_EXEC_SP_RUN_PIPELINE, thread_hint=2,
        indent=8,
    )
    chargement = build_seq_chargement_staging()
    push = build_seq_push_dwh()

    # Precedences interieures : SQL_Lire -> SEQ_Chargement -> SQL_Exec -> SEQ_Push
    pc1 = precedence_xml(parent, "SQL_Lire_Watermark", "SEQ_Chargement_Staging",
                         pc_name="PC_Lire_to_Chargement", indent=8)
    pc2 = precedence_xml(parent, "SEQ_Chargement_Staging", "SQL_Exec_sp_run_pipeline",
                         pc_name="PC_Chargement_to_Exec", indent=8)
    pc3 = precedence_xml(parent, "SQL_Exec_sp_run_pipeline", "SEQ_Push_DWH",
                         pc_name="PC_Exec_to_Push", indent=8)

    return f'''      <DTS:Executable
        DTS:refId="{parent}"
        DTS:CreationName="STOCK:SEQUENCE"
        DTS:Description="Conteneur de séquences"
        DTS:DTSID="{guid("seq", parent)}"
        DTS:ExecutableType="STOCK:SEQUENCE"
        DTS:LocaleID="-1"
        DTS:ObjectName="SEQ_Pipeline_Complet">
        <DTS:Variables />
        <DTS:Executables>
{sql_lire}
{chargement}
{sql_exec}
{push}
        </DTS:Executables>
        <DTS:PrecedenceConstraints>
{pc1}
{pc2}
{pc3}
        </DTS:PrecedenceConstraints>
      </DTS:Executable>'''


# ============================================================================
# DesignTimeProperties (layout minimal)
# ============================================================================

def design_time_properties() -> str:
    """Section CDATA contenant le layout. Minimal : juste declarer le Package
    sans positions explicites -- SSDT reorganisera automatiquement."""
    return '''  <DTS:DesignTimeProperties><![CDATA[<?xml version="1.0"?>
<!--Cette section CDATA contient des informations sur la disposition du package.-->
<!--Si vous modifiez manuellement cette section et commettez une erreur, vous pouvez la supprimer.-->
<!--Le package pourra toujours se charger normalement, mais les informations de disposition precedente seront perdues et le concepteur reorganisera automatiquement les elements sur l'aire de conception.-->
<Objects Version="8">
  <Package design-time-name="Package">
    <LayoutInfo>
      <GraphLayout Capacity="32" xmlns="clr-namespace:Microsoft.SqlServer.IntegrationServices.Designer.Model.Serialization;assembly=Microsoft.SqlServer.IntegrationServices.Graph" xmlns:mssgle="clr-namespace:Microsoft.SqlServer.Graph.LayoutEngine;assembly=Microsoft.SqlServer.Graph" xmlns:assembly="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:s="clr-namespace:System;assembly=mscorlib">
      </GraphLayout>
    </LayoutInfo>
  </Package>
</Objects>]]></DTS:DesignTimeProperties>'''


# ============================================================================
# Package final
# ============================================================================

def build_package() -> str:
    now = _ssis_datetime(_dt.datetime.now())
    pkg_dtsid = guid("package", "Orion_Pipeline_Quotidien")
    ver_guid  = guid("pkg_version", "Orion_Pipeline_Quotidien")
    seq_complet = build_seq_pipeline_complet()

    return f'''<?xml version="1.0"?>
<DTS:Executable xmlns:DTS="www.microsoft.com/SqlServer/Dts"
  DTS:refId="Package"
  DTS:CreationDate="{now}"
  DTS:CreationName="Microsoft.Package"
  DTS:CreatorComputerName="{CREATOR_COMPUTER}"
  DTS:CreatorName="{CREATOR_USER}"
  DTS:DTSID="{pkg_dtsid}"
  DTS:ExecutableType="Microsoft.Package"
  DTS:LastModifiedProductVersion="17.0.1016.0"
  DTS:LocaleID="1036"
  DTS:ObjectName="Orion_Pipeline_Quotidien"
  DTS:PackageType="5"
  DTS:VersionBuild="1"
  DTS:VersionGUID="{ver_guid}">
  <DTS:Property
    DTS:Name="PackageFormatVersion">8</DTS:Property>
{variables_xml()}
  <DTS:Executables>
{seq_complet}
  </DTS:Executables>
{design_time_properties()}
</DTS:Executable>
'''


def main() -> None:
    xml = build_package()
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    n_lines = sum(1 for _ in xml.splitlines())
    print(f"OK -> {OUT}")
    print(f"     {n_lines} lignes, {len(xml.encode('utf-8')):,} octets")
    print(f"     {len(STAGING_DFTS)} DFT staging + {len(DWH_DFTS)} DFT DWH")


if __name__ == "__main__":
    main()
