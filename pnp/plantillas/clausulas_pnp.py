"""The tokenized English clause library for the Ecosystem Plus Membership template.

The wording follows Plug and Play's real Ecosystem Plus Membership Agreement.
Every value that changes per deal is a Context Service merge token resolved from
PNP_ContractDocGenContext when the document is generated.

This module is also imported by build_pnp_contract_tokens.py, which writes the
same clause bodies into the template's clause content controls. Server-side
generation does not re-read the library, so the text has to live in both places
and this keeps them identical.

Tokens are deliberately limited to language-neutral fields. PnP_Membership_Term__c
and PnP_Event_Format__c hold Spanish picklist values ("12 meses", "Presencial")
that would break an English document, so the term is rendered from ContractTerm.

Start date, term and program values are Data True-Up (DT_) tokens that live once
in the template body (introduction and Program Terms), so clauses refer to them
instead of repeating them.

Usage:
  python3 clausulas_pnp.py [--org plug-and-play-trailsignup] [--only NAME]
"""

import argparse
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "rlm-base-dev" / "scripts"))
from sf_token import org_auth  # noqa: E402

API = "v68.0"
CATEGORY = "Plug_and_Play"

# Token name -> value type for the DocumentClauseContentToken records. A clause
# cannot be activated while a token in its body has no record.
TOKEN_TYPES = {
    "AccountName": "String",
    "AccountIndustry": "String",
    "ContractNumber": "String",
    "ContractEndDate": "Date",
    "PnPContractValue": "Currency",
    "PnPDiscountApprover": "String",
    "PnPSourceQuoteNumber": "String",
}

# name: clause library record name, also the title shown in the Word add-in.
# heading: the numbered heading printed in the document.
# body: one entry per paragraph.
CLAUSES = [
    {
        "name": "Scope of the Agreement",
        "heading": "1. THE SCOPE OF THE AGREEMENT",
        "body": [
            "{{AccountName}} (\u201cClient\u201d), a company operating in the {{AccountIndustry}} industry, "
            "is seeking a deeper engagement with Plug and Play to drive business growth opportunities "
            "through engagement, partnership, pilots, acquisition, or investment in startups. To ensure "
            "Client\u2019s success as a strategic member of Plug and Play\u2019s ecosystem, Plug and Play "
            "will provide the services described in this Agreement in exchange for the fees described in "
            "Exhibit A, attached and incorporated into this Agreement.",
            "The execution of this Agreement grants Client the status of \u201cEcosystem Plus Member\u201d "
            "of the Program for the membership term set out in the Program Terms, commencing on the "
            "Effective Date and continuing until {{ContractEndDate}} (the \u201cTerm\u201d).",
        ],
    },
    {
        "name": "Ecosystem Plus Benefits",
        "heading": "2. ECOSYSTEM PLUS BENEFITS",
        "body": [
            "As an Ecosystem Plus Member, Client will receive the following services within the Term.",
            "2.1. Relationship Management. Plug and Play designates the relationship manager named in the "
            "Program Terms as Client\u2019s dedicated relationship manager throughout the Term. The relationship manager serves as "
            "Client\u2019s primary point of contact and supports Client\u2019s innovation scouting, startup "
            "engagement, and ecosystem networking activities. The Parties shall hold regular check-in "
            "meetings, on a biweekly or monthly basis, to discuss ongoing activities, areas of interest, "
            "and upcoming opportunities. Client\u2019s executive sponsor for the Program is the person "
            "named in the Program Terms.",
            "2.2. Elite List and Selection Process. Upon the selection of the focus area for the Batch, "
            "Plug and Play will source, review, and vet applicants to compile a list of qualified startups "
            "(the \u201cElite List\u201d). Client will receive the Elite List and may assist Plug and Play in "
            "the selection of startups for the Program.",
            "2.3. Dealflow Sessions and Ad-Hoc Introductions. Plug and Play will facilitate private "
            "introductions between Client and startups based on Client\u2019s business challenges, and will "
            "make ad-hoc introductions as new opportunities arise during the Term.",
            "2.4. Events and Workshops. Plug and Play will deliver the number of workshops set out in the "
            "Program Terms during the Term and Client may attend any community event hosted during the "
            "Term. The Program kickoff will take place on the kickoff date set out in the Program Terms.",
            "2.5. Playbook. During the Term, Client may access Plug and Play\u2019s proprietary virtual "
            "platform called \u201cPlaybook,\u201d which allows corporate members to track engagement with "
            "startups and includes a database of startup profiles.",
        ],
    },
    {
        "name": "Authorization for Use of Name, Trademarks and Logos",
        "heading": "3. AUTHORIZATION FOR USE OF NAME, TRADEMARK(S), LOGO(S) AND OTHER IDENTIFYING MARKS",
        "body": [
            "{{AccountName}} grants Plug and Play a limited, non-exclusive, non-transferable, revocable "
            "license during the Term to use Client\u2019s logo and trademarks (\u201cMarks\u201d) on a placard "
            "at Plug and Play\u2019s Silicon Valley facility, at Plug and Play events and in its promotional "
            "materials, and on Plug and Play\u2019s website.",
            "Except for the uses listed above, Plug and Play will ask for written permission from Client to "
            "use its Marks, which shall not be unreasonably withheld. Client retains all intellectual "
            "property rights, title and interest in or to any of its Marks. Plug and Play\u2019s use of the "
            "Marks shall comply with Client\u2019s then-current brand guidelines, and Plug and Play shall "
            "promptly correct or discontinue any non-compliant use upon Client\u2019s request.",
            "Any press release, public announcement, case study, testimonial, endorsement, marketing "
            "campaign, or social media posting specifically identifying {{AccountName}} or describing "
            "Client\u2019s participation in the Program shall require Client\u2019s prior written approval. "
            "Plug and Play allocates the marketing hours set out in the Program Terms to Client during "
            "the Term.",
        ],
    },
    {
        "name": "Intellectual Property",
        "heading": "4. INTELLECTUAL PROPERTY",
        "body": [
            "Each Party has, prior to this Agreement, created, acquired or otherwise obtained rights to its "
            "respective proprietary information related to technology, business, products, processes, "
            "services, or operations, including any registered or potentially registrable patents, "
            "trademarks, logos, or designs, as well as copyrightable works, trade secrets, and know-how "
            "(\u201cBackground Intellectual Property\u201d). Each Party shall, for the duration of this "
            "Agreement and thereafter, retain the ownership of its own Background Intellectual Property.",
            "Plug and Play shall acquire no right, title or interest in or to any intellectual property, "
            "including all logos, trademarks, names, ideas, concepts, creative materials, work product and "
            "data, and any inventions and discoveries first conceived or developed by or between "
            "{{AccountName}} and any entity introduced to Client through Plug and Play\u2019s services or in "
            "connection with this Agreement.",
            "If the Parties desire to jointly develop any intellectual property during the Term, they shall "
            "execute a separate development agreement before starting any such development.",
        ],
    },
    {
        "name": "Confidentiality",
        "heading": "5. CONFIDENTIALITY",
        "body": [
            "Prior to and during the Term, each Party (the \u201cReceiving Party\u201d) may be exposed to "
            "certain valuable information of the other Party (the \u201cDisclosing Party\u201d) that the "
            "Disclosing Party deems confidential, including trade secrets, business and marketing plans, "
            "financial information, customer lists, the terms of this Agreement, and any non-public "
            "information relating to Client\u2019s activities, evaluations, engagements, or usage of the "
            "Playbook platform (\u201cConfidential Information\u201d).",
            "The Receiving Party shall keep the Confidential Information confidential, protect it to the "
            "same extent it protects its own confidential information and in no event with less than "
            "reasonable care, and use it only in furtherance of this Agreement. This provision shall survive "
            "the expiration or earlier termination of this Agreement and shall continue for a period of "
            "three (3) years after {{ContractEndDate}}.",
            "These obligations do not apply to information that was in the Receiving Party\u2019s possession "
            "before disclosure, was or became part of the public domain through no fault of the Receiving "
            "Party, was legally received from a third party without a confidentiality obligation, or is "
            "required by law, regulation, subpoena, or court order to be disclosed.",
        ],
    },
    {
        "name": "Limitation of Liability",
        "heading": "6. LIMITATION OF LIABILITY",
        "body": [
            "Except for the indemnification obligations set out in this Agreement, the liability of either "
            "Party under this Agreement shall be limited to the total amount of fees paid by {{AccountName}} "
            "to Plug and Play under agreement {{ContractNumber}}, being USD {{PnPContractValue}}. In no event "
            "shall either Party be liable to the other Party for any special, incidental, punitive, or "
            "consequential damages.",
        ],
    },
    {
        "name": "Term, Billing and Payment",
        "heading": "7. TERM, BILLING AND PAYMENT",
        "body": [
            "The Term of this Agreement commences on the Effective Date and continues until "
            "{{ContractEndDate}}, covering the membership term set out in the Program Terms. The fees "
            "for the Term are set out in Exhibit A: Fee Schedule and total USD {{PnPContractValue}}, as quoted "
            "in proposal {{PnPSourceQuoteNumber}}.",
            "Plug and Play will invoice {{AccountName}} on the first date of each Segment, in the amount "
            "designated for that Segment. Client shall pay Plug and Play no later than 30 days after receipt "
            "of an invoice. Payments made under this Agreement are made in advance and are not refundable. "
            "Client\u2019s failure to pay any amount when due may result in a late penalty commencing on the "
            "due date until the date paid at a rate of 1.5% per month (18% per annum), or the maximum amount "
            "allowed by law, whichever is less.",
            "All amounts payable under this Agreement are exclusive of any taxes or other government charges "
            "incurred by Plug and Play as a result of the provision of the services to Client.",
        ],
    },
    {
        "name": "Termination, Refund and Renewal",
        "heading": "8. TERMINATION, REFUND AND RENEWAL",
        "body": [
            "{{AccountName}} may terminate this Agreement effective at the end of each Segment by providing "
            "Plug and Play with written notice of its intent to terminate no later than 30 days prior to the "
            "end of the then-current Segment. Early termination by Client shall not entitle Client to any "
            "refund of fees previously paid, nor release Client from the obligation to pay fees already "
            "invoiced pursuant to Exhibit A that remain unpaid as of the effective date of termination.",
            "Either Party may terminate this Agreement for the other Party\u2019s material breach by "
            "providing written notice. The breaching Party shall have 90 days to cure such material breach. "
            "If Plug and Play fails to continue the Program, Plug and Play shall promptly refund any prepaid "
            "fees attributable to the unused portion of the then-current Segment on a pro rata basis.",
            "This Agreement is scheduled for renewal review on the date set out in the Program Terms. "
            "Renewal fees for the following term will be presented to Client at least 60 days before "
            "that date.",
        ],
    },
]


def clause_html(clause):
    paragraphs = [f"<p><b>{clause['heading']}</b></p>"]
    paragraphs += [f"<p>{text}</p>" for text in clause["body"]]
    return "".join(paragraphs)


def tokens_in(clause):
    """Merge token names used by a clause, in order of first appearance."""
    seen = []
    for text in clause["body"]:
        rest = text
        while "{{" in rest:
            rest = rest.split("{{", 1)[1]
            name, rest = rest.split("}}", 1)
            if name not in seen:
                seen.append(name)
    return seen


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


def ensure_set(org, name):
    """One clause set per clause: a set holds a single main clause per language."""
    found = org.query(f"SELECT Id FROM DocumentClauseSet WHERE Name = '{name}'")
    if found:
        return found[0]["Id"]
    # The picklist stores the 15-character category id, not the 18-character one.
    category = org.query("SELECT Id FROM ClauseCatgConfiguration "
                         f"WHERE DeveloperName = '{CATEGORY}'")[0]["Id"][:15]
    return org.call("POST", "sobjects/DocumentClauseSet", {
        "Name": name,
        "DefaultLanguage": "en_US",
        "Category": category,
    })["id"]


def ensure_clause(org, set_id, clause):
    name = clause["name"]
    found = org.query("SELECT Id FROM DocumentClause "
                      f"WHERE Name = '{name}' AND DocumentClauseSetId = '{set_id}'")
    body = {
        "Name": name,
        "Content": clause_html(clause),
        "Format": "Rich_Text",
        "Language": "en_US",
        "DocumentClauseSetId": set_id,
        "IsAlternateClause": False,
    }
    if found:
        clause_id = found[0]["Id"]
        # Content is only editable in draft, so an active clause is reopened first.
        org.call("PATCH", f"sobjects/DocumentClause/{clause_id}", {"Status": "Draft"})
        org.call("PATCH", f"sobjects/DocumentClause/{clause_id}", body)
    else:
        # A clause can only be born as a draft; it is activated once its tokens exist.
        clause_id = org.call("POST", "sobjects/DocumentClause",
                             {**body, "Status": "Draft"})["id"]

    wanted = tokens_in(clause)
    existing = {t["Name"]: t["Id"] for t in org.query(
        f"SELECT Id, Name FROM DocumentClauseContentToken WHERE DocumentClauseId = '{clause_id}'")}
    for token in wanted:
        if token in existing:
            continue
        org.call("POST", "sobjects/DocumentClauseContentToken", {
            "Name": token,
            "DocumentClauseId": clause_id,
            "TokenType": "Merge",
            "ValueType": TOKEN_TYPES.get(token, "String"),
        })
    for token, token_id in existing.items():
        if token not in wanted:
            org.call("DELETE", f"sobjects/DocumentClauseContentToken/{token_id}")

    org.call("PATCH", f"sobjects/DocumentClause/{clause_id}", {"Status": "Active"})
    return clause_id


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--org", default="plug-and-play-trailsignup")
    parser.add_argument("--only", help="Publish just this clause")
    args = parser.parse_args()

    org = Org(args.org)
    for clause in CLAUSES:
        if args.only and args.only != clause["name"]:
            continue
        set_id = ensure_set(org, clause["name"])
        clause_id = ensure_clause(org, set_id, clause)
        print(f"  {clause_id}  {clause['name']}  tokens: {', '.join(tokens_in(clause)) or '-'}")


if __name__ == "__main__":
    main()
