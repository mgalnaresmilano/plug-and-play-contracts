"""Publish a Microsoft 365 Word CLM template (Context Service) to the org.

Creates the DocumentTemplate, uploads the .docx to the Docgen library and links
both through DocumentTemplateContentDoc. If the template already exists, it is
set to Draft, a new file version is uploaded and it is reactivated.

Usage:
  python3 publicar_plantilla.py <Name> <file.docx> \
      [--context PNP_ContractDocGenContext] [--mapping PnpContractMapping] \
      [--org plug-and-play-trailsignup]
"""

import argparse
import base64
import re
import sys
import zipfile
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "rlm-base-dev" / "scripts"))
from sf_token import org_auth  # noqa: E402

API = "v68.0"
LIBRARY_NAME = "Docgen Document Template Library"


class Org:
    def __init__(self, org):
        self.base, token = org_auth(org)
        self.headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def call(self, method, path, body=None):
        resp = requests.request(method, f"{self.base}/services/data/{API}/{path}",
                                headers=self.headers, json=body)
        if resp.status_code >= 400:
            sys.exit(f"ERROR {method} {path} ({resp.status_code}): {resp.text}")
        return resp.json() if resp.content else None

    def query(self, soql):
        return self.call("GET", f"query?q={requests.utils.quote(soql)}")["records"]


def token_list(path):
    """Build DocumentTemplate.TokenList the way the template designer does:
    comma-separated, nested tokens prefixed with their sections
    (Quote:LineItems:ProductName), section markers excluded."""
    with zipfile.ZipFile(path) as docx:
        parts = sorted(n for n in docx.namelist()
                       if re.fullmatch(r"word/(document|header\d*|footer\d*)\.xml", n))
        text = "".join(re.sub(r"<[^>]+>", "", docx.read(n).decode("utf-8")) for n in parts)
    tokens, sections = [], []
    for raw in re.findall(r"\{\{\s*([^{}]+?)\s*\}\}", text):
        if raw.startswith("#"):
            sections.append(raw[1:])
        elif raw.startswith("/"):
            if sections and sections[-1] == raw[1:]:
                sections.pop()
        else:
            token = ":".join(sections + [raw])
            if token not in tokens:
                tokens.append(token)
    return ",".join(tokens)


def upload_new(org, name, data):
    """Upload a new file to the Docgen library and return its ContentDocumentId."""
    existing = org.query("SELECT ContentDocumentId FROM ContentVersion "
                         f"WHERE Title = '{name}' AND IsLatest = true")
    if existing:
        doc_id = existing[0]["ContentDocumentId"]
        org.call("POST", "sobjects/ContentVersion", {
            "ContentDocumentId": doc_id, "Title": name,
            "PathOnClient": f"{name}.docx", "VersionData": data,
        })
        return doc_id
    library = org.query(f"SELECT Id FROM ContentWorkspace WHERE Name = '{LIBRARY_NAME}'")
    version = org.call("POST", "sobjects/ContentVersion", {
        "Title": name, "PathOnClient": f"{name}.docx",
        "VersionData": data, "FirstPublishLocationId": library[0]["Id"],
    })
    return org.query("SELECT ContentDocumentId FROM ContentVersion "
                     f"WHERE Id = '{version['id']}'")[0]["ContentDocumentId"]


def link_file(org, template_id, doc_id):
    org.call("POST", "sobjects/DocumentTemplateContentDoc", {
        "Name": f"{template_id[:15]}_{doc_id[:15]}",
        "DocumentTemplateId": template_id,
        "ContentDocumentId": doc_id,
        "FileStageType": "Original",
    })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("file")
    parser.add_argument("--context", default="PNP_ContractDocGenContext")
    parser.add_argument("--mapping", default="PnpContractMapping")
    parser.add_argument("--org", default="plug-and-play-trailsignup")
    args = parser.parse_args()

    org = Org(args.org)
    data = base64.b64encode(Path(args.file).read_bytes()).decode()
    existing = org.query(f"SELECT Id FROM DocumentTemplate WHERE Name = '{args.name}'")

    if existing:
        template_id = existing[0]["Id"]
        print(f"Updating {args.name} ({template_id})")
        org.call("PATCH", f"sobjects/DocumentTemplate/{template_id}",
                 {"IsActive": False, "Status": "Draft"})
        link = org.query("SELECT ContentDocumentId FROM DocumentTemplateContentDoc "
                         f"WHERE DocumentTemplateId = '{template_id}'")
        if link:
            org.call("POST", "sobjects/ContentVersion", {
                "ContentDocumentId": link[0]["ContentDocumentId"], "Title": args.name,
                "PathOnClient": f"{args.name}.docx", "VersionData": data,
            })
        else:
            doc_id = upload_new(org, args.name, data)
            link_file(org, template_id, doc_id)
    else:
        doc_id = upload_new(org, args.name, data)
        template_id = org.call("POST", "sobjects/DocumentTemplate", {
            "Name": args.name,
            "Type": "Microsoft365Word",
            "TokenMappingType": "JSON",
            "TokenMappingMethodType": "ContextService",
            "UsageType": "Contract_Lifecycle_Management",
            "DocumentGenerationMechanism": "ServerSide",
            "ContextDefinitionName": args.context,
            "ContextMappingName": args.mapping,
            "Status": "Draft",
            "IsActive": False,
        })["id"]
        link_file(org, template_id, doc_id)
        print(f"Created {args.name} ({template_id}), file {doc_id}")

    tokens = token_list(args.file)
    org.call("PATCH", f"sobjects/DocumentTemplate/{template_id}", {"TokenList": tokens})
    print(f"TokenList: {tokens.count(',') + 1 if tokens else 0} tokens")
    org.call("PATCH", f"sobjects/DocumentTemplate/{template_id}",
             {"IsActive": True, "Status": "Active"})
    print(f"Active: {args.name} ({template_id})")


if __name__ == "__main__":
    main()
