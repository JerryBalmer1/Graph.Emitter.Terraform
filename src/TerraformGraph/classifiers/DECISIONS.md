# Classifier decisions

Append-only. Every judgement behind `drawers.json`, `map.json` and the classifier code gets a numbered entry: Question, Call, Rejected, Why, Cost if wrong. Never edit an earlier entry. To change a call, append a new entry that says "Supersedes N" and explain what changed. Map rows cite entries as `(see DECISIONS N)`.

Read this file before any classifier work. Append an entry for every judgement you make, including each subcategory you decide not to map. Never add or change a `map.json` row without a reason.

---

## 1. Which drawers exist

- Question: What is the fixed top-level list map rows can target?
- Call: network, compute, storage, database, identity, security, messaging, observability, management, devops, containers, serverless, dns, cdn, analytics, ai, iot, media, migration, unclassified. That is twenty, in that order, which is also the order of the `Drawers` summary.
- Rejected: A per-provider drawer list; the cloud vendors' own portal categories (each vendor's differ, so the list would not cross providers); a two-level tree.
- Why: One flat list that every provider maps into is what lets a view collapse a mixed azurerm + vsphere + azuredevops graph the same way. The list was given as the starting point for 0.12.0 and covers every azurerm, azuredevops and vsphere subcategory except those recorded below.
- Cost if wrong: Adding a drawer is cheap: append it to `drawers.json`, re-point rows with a new entry, rerun BuildClassifier. Renaming or removing one breaks anyone filtering on the old name.

## 2. No integration drawer

- Question: azurerm has API gateway and workflow labels (API Management, Connections, Logic App). Should there be an integration drawer?
- Call: No new drawer. Logic App maps to serverless, because workflows run per trigger with no servers. API Management and Connections stay unmapped (entries 27 and 29).
- Rejected: Adding `integration` now; forcing API Management into network.
- Why: The drawer list was fixed for this release (entry 1), and an API gateway is not network plumbing in the sense the network drawer means.
- Cost if wrong: 67 azurerm types sit in unclassified. If integration is added later, those two labels and probably Logic App move with a superseding entry.

## 3. Where classifier files live, and lookup order

- Question: Where do drawers.json, map.json and the per-provider classifiers live, and which copy wins?
- Call: Bundled in the module at `src/TerraformGraph/classifiers/` (committed, shipped). `New-TerraformClassifier` writes to `$env:LOCALAPPDATA\TerraformGraph\classifiers` by default. Lookup order is `-ClassifierPath`, then the user folder, then the bundled folder.
- Rejected: A repo-root `classifiers/` (it would not ship with the module); writing into the module folder by default (an installed module folder may be read-only, and an upgrade would wipe it).
- Why: It mirrors the registry cache (user file over bundled file) and keeps BuildClassifier's output next to the code that reads it.
- Cost if wrong: Moving the folder means changing `$script:TerraformClassifierBundledRoot` and the docs.

## 4. Precedence is per provider, not per file

- Question: With no `-Version`, if the user folder has azurerm 5.7.0 and the bundled folder has 5.8.0, which is used?
- Call: The first folder in the lookup order that holds the provider at all supplies it, at its newest version there, so 5.7.0 wins. With `-Version`, the first file at that version wins whatever folder it is in.
- Rejected: Newest version across all folders.
- Why: An override has to win, or the only way to replace a bundled classifier would be to match its version number.
- Cost if wrong: A stale user classifier can hide a newer bundled one. `Get-TerraformClassifier` shows the `Path` it used.

## 5. How rows match

- Question: How does a doc subcategory find its row?
- Call: Exact text, ignoring case (ordinal). A row whose provider is the type's provider address wins over a `*` row. No trimming, plural folding or fuzzy matching.
- Rejected: Fuzzy or substring matching, which would let "Network" catch "Network Function" or "Private DNS Resolver" catch "DNS".
- Why: Rows have to be predictable. A label the map does not match is a finding, which is the point.
- Cost if wrong: A provider that renames a label (say "Container" to "Containers") drops those types to unclassified until a row is added. Findings show it.

## 6. mapVersion is a hash

- Question: What is `mapVersion` in a classifier file?
- Call: The first 12 hex digits of the sha256 of map.json's compact JSON, after parsing.
- Rejected: A hand-bumped version number in map.json; a hash of the file bytes.
- Why: It changes exactly when the rows change, nobody can forget to bump it, and whitespace or CRLF/LF checkouts do not change it.
- Cost if wrong: It is opaque. To find which map a classifier came from, hash candidate maps or check git history.

## 7. generatedOn is kept when nothing changed

- Question: How can reruns be byte-identical when the file carries `generatedOn`?
- Call: If the file already exists and the new content matches it apart from `generatedOn` (ignoring CRLF/LF), the file is left alone and the status is `Unchanged`. Otherwise `generatedOn` is the current UTC time.
- Rejected: Leaving out `generatedOn`; a date-only stamp, which would differ on the next day.
- Why: Committed classifiers should not churn in git when a release rebuilds them from the same inputs.
- Cost if wrong: `generatedOn` means "when this content was first written", not "when the command last ran".

## 8. Types come from the schema, not the docs

- Question: What is the list of types a classifier covers?
- Call: Every resource and data source type in the cached schema. A doc page whose Id is `/unmatched/` (no such schema type) is left out of the classifier. A schema type with no page is a `NoDocPage` finding.
- Rejected: Classifying doc pages.
- Why: The overlay decorates schema and resource nodes, which are schema types. Unmatched pages are already counted in the docs cache's `UnmatchedCount`.
- Cost if wrong: An unmatched page's subcategory is not used. Today that is 1 azurerm page and 1 azuredevops page.

## 9. Which versions a classifier is built from

- Question: The schema and docs caches may hold different versions. What is the classifier's `version`?
- Call: `version` is the schema version (`-Version`, default newest cached). Docs are read at the same version, else the newest cached docs with a warning, and `docsVersion` says which. `BuildClassifier` passes the registry cache's latest version, like BuildSchemaPack.
- Rejected: Requiring identical versions; naming the file after the docs version.
- Why: The types come from the schema (entry 8), so the schema version is what the file describes. Subcategory labels change slowly enough that docs one version off are still useful, and `docsVersion` makes the mismatch visible.
- Cost if wrong: A type added in the newer schema gets `NoDocPage` until the docs catch up.

## 10. azuredevops has no subcategories

- Question: azuredevops 1.16.0 has an empty subcategory on all 177 resource and data source pages. Confirmed against `/v2/provider-docs/<id>` (attribute null, no `subcategory:` in the front matter). Should the whole provider map to devops?
- Call: No. All 177 types are unclassified: 176 `NoSubcategory`, 1 `NoDocPage` (azuredevops_environment_resource_kubernetes).
- Rejected: A provider-wide default drawer (a new map feature: "every azuredevops type is devops"); classifying by type-name prefix.
- Why: The default classifier is derived from the provider's own labels. Inventing labels for a provider that publishes none would be hand-sorting, and the finding tells the provider's maintainers something true.
- Cost if wrong: An azuredevops-heavy view collapses to one unclassified drawer. A provider-default row is the obvious next feature; add it with a superseding entry if wanted.

## 11. Overlay: nested nodes inherit their type's drawer

- Question: With `ConvertTo-TerraformSchemaGraph -Classify`, which nodes get Drawer and Subcategory?
- Call: Every SchemaNode gets both properties. Resource and DataSource nodes take their classifier's values. Their Block and Attribute descendants take the same values. Provider, provider config and Function nodes get `$null`. The values are set when each node is built, because adding note properties afterwards cost about 3.6 s on azurerm's 33,699 nodes.
- Rejected: Only type nodes carry the properties; a separate lookup table on the graph.
- Why: Collapsing a view by drawer has to take a type's whole subtree with it. Without -Classify the nodes are unchanged.
- Cost if wrong: `Nodes | Where-Object Drawer -eq storage` returns attributes too. Filter on `Kind` for types.

## 12. Overlay: a provider with no classifier

- Question: What does -Classify do for a provider that has no classifier, or a type its classifier lacks?
- Call: Drawer `unclassified`, Subcategory `$null`, and one warning per provider naming New-TerraformClassifier and -ClassifierPath. `terraform.io/builtin/terraform` (terraform_data) is unclassified with no warning, since it has no registry docs.
- Rejected: `$null` Drawer for "not classified at all"; a terminating error.
- Why: unclassified is a legitimate drawer, and every node of a classified type must land in some drawer for the summary to add up to the type count.
- Cost if wrong: "No classifier" and "classifier says unclassified" look the same on a node. The warning tells them apart.

## 13. -ClassifierPath implies -Classify

- Question: Should -ClassifierPath without -Classify do anything?
- Call: Yes. Passing -ClassifierPath turns classification on.
- Rejected: Ignoring it unless -Classify is also given.
- Why: Passing a classifier and silently getting an unclassified graph is a trap.
- Cost if wrong: None known.

## 14. App Service is compute, not serverless

- Question: azurerm's "App Service (Web Apps)" holds web apps and function apps (azurerm_linux_function_app and others). Compute or serverless?
- Call: compute.
- Rejected: serverless; splitting by type name.
- Why: The label is about App Service plans, which are managed servers. Function apps on a consumption plan are serverless, but the label does not say which plan. Rows map labels, not types.
- Cost if wrong: Function apps do not appear in the serverless drawer, which then holds only Logic Apps (19 types).

## 15. azurerm "Base" is management

- Question: "Base" names nothing. Map it or leave it?
- Call: management. Its types are resource groups, subscriptions, provider registrations, locations and client config.
- Rejected: Leaving it unmapped because the label is meaningless.
- Why: Every type under the label is management-plane scaffolding, and the label is stable across azurerm releases.
- Cost if wrong: 11 types. If azurerm ever files something unrelated under Base, it lands in management silently.

## 16. Backup is storage

- Question: Where do backup vaults go (azurerm DataProtection and Recovery Services)?
- Call: storage. drawers.json says the storage drawer includes backup.
- Rejected: security (data protection); migration (site recovery replicates servers); a backup drawer.
- Why: Backups are copies of data held in vaults. Recovery Services mixes backup and site recovery under one label, and backup is most of it.
- Cost if wrong: 45 types. Site recovery types (azurerm_site_recovery_*) arguably belong in migration.

## 17. Hybrid Compute is management

- Question: azurerm "Hybrid Compute" (azurerm_arc_machine, extensions, private link scope): compute or management?
- Call: management, like "Arc Resource Bridge".
- Rejected: compute.
- Why: Arc-enabled machines are existing servers projected into Azure to be managed. Azure is not providing the compute. By contrast "Azure Stack HCI" and "System Center Virtual Machine Manager" create VMs and map to compute.
- Cost if wrong: 4 types.

## 18. Lighthouse is identity

- Question: azurerm "Lighthouse" (definitions and assignments): management or identity?
- Call: identity.
- Rejected: management.
- Why: A Lighthouse definition grants principals in another tenant roles on a scope. That is delegated access, the same thing "Authorization" role assignments do.
- Cost if wrong: 2 types.

## 19. Palo Alto is security; Azure Firewall stays in network

- Question: azurerm "Palo Alto" (next-generation firewalls and rulestacks) maps to security, while azurerm_firewall sits under the "Network" label and so in network. Is that inconsistent?
- Call: Yes, and it is accepted. Palo Alto maps to security. Azure Firewall stays where its label puts it.
- Rejected: Overriding single types; mapping Palo Alto to network for symmetry.
- Why: Rows map labels, not types (entry 5). The provider files Azure Firewall under Network and Palo Alto under its own label. The security drawer description names third-party firewalls.
- Cost if wrong: Firewalls are split across two drawers. A type-level override would be a new map feature.

## 20. Service Fabric is compute

- Question: "Service Fabric" and "Service Fabric Managed Clusters": containers or compute?
- Call: compute.
- Rejected: containers.
- Why: Service Fabric clusters are VM scale sets running Microsoft's own orchestrator, not Kubernetes or a container runtime first. The containers drawer means Kubernetes, registries and container apps.
- Cost if wrong: 2 types.

## 21. vsphere Security is identity, overriding the * row

- Question: The `*` row maps "Security" to security. vsphere's "Security" label holds vsphere_role, vsphere_entity_permissions, vsphere_sso_user and vsphere_sso_group. Which drawer?
- Call: A vsphere row maps "Security" to identity and overrides the `*` row.
- Rejected: Accepting security for vsphere; dropping the `*` Security row.
- Why: Users, groups, roles and permissions are what the identity drawer means. The `*` row stays for providers whose Security label holds real security services. This is also the case that proves provider rows beat `*` rows.
- Cost if wrong: 7 types.

## 22. Which labels get * rows

- Question: Which subcategories map for every provider (`provider: "*"`)?
- Call: Only labels that name a drawer outright: CDN, Compute, Database, DNS, Management, Messaging, Network, Networking, Security, Storage.
- Rejected: `*` rows for vendor-flavoured labels ("Container", "Monitor", "Key Vault").
- Why: A `*` row also decides for providers nobody has reviewed. Only labels whose meaning cannot vary safely do that.
- Cost if wrong: A new provider whose "Database" label holds something else lands in the wrong drawer silently, until someone reads its classifier.

## 23. Where a judgement is recorded

- Question: Does every mapped row need a DECISIONS entry?
- Call: No. A row whose label plainly names the drawer's domain is recorded by its `reason` alone. A row that someone could reasonably argue the other way gets an entry, and its reason cites it. Every unmapped label gets an entry.
- Rejected: One entry per row (about 110 entries of "Key Vault is security").
- Why: This file is for the calls worth arguing about. The row reason is enough for the rest, and the lint keeps reasons from being empty.
- Cost if wrong: A future agent may treat an uncited row as uncontroversial when it is not. Add an entry when you disagree with one.

## 24. Caches are databases

- Question: azurerm "Redis" and "Managed Redis": database, or something else?
- Call: database. drawers.json says the database drawer includes caches.
- Rejected: compute; a cache drawer.
- Why: Redis is a managed key-value store, and teams provision it next to their databases.
- Cost if wrong: 11 types.

## 25. Communication Services is messaging

- Question: azurerm "Communication" (Communication Services, email domains and sender usernames): where?
- Call: messaging.
- Rejected: Leaving it unmapped; ai.
- Why: The types deliver email and SMS, which the messaging drawer description includes as notification delivery.
- Cost if wrong: 6 types.

## 26. Test services are devops

- Question: azurerm "Chaos Studio" and "Load Test": devops or observability?
- Call: devops.
- Rejected: observability.
- Why: Chaos experiments and load tests are run as part of delivery. They produce signals, but they are not monitoring.
- Cost if wrong: 7 types.

## 27. Unmapped: azurerm "API Management"

- Question: Map API Management (64 types: azurerm_api_management and its APIs, operations, policies, products)?
- Call: Leave unmapped. 64 types are unclassified, `UnmappedSubcategory`.
- Rejected: network (it is an API gateway, but not network plumbing); management (it manages APIs, not Azure); serverless.
- Why: It belongs in an integration drawer, which the list does not have (entry 2).
- Cost if wrong: This is the largest unclassified block in azurerm: 64 of its 101 findings.

## 28. Unmapped: azurerm "App Configuration"

- Question: Map App Configuration (6 types: stores, keys, feature flags)?
- Call: Leave unmapped.
- Rejected: devops (feature flags are a delivery tool); management; security.
- Why: It is runtime application configuration. No drawer describes that, and each candidate is a stretch.
- Cost if wrong: 6 types.

## 29. Unmapped: azurerm "Connections"

- Question: Map Connections (azurerm_api_connection, managed APIs: 3 types)?
- Call: Leave unmapped.
- Rejected: serverless, which would put it with Logic App.
- Why: These are integration connectors used by Logic Apps and Power Platform (entry 2). A connector is not itself serverless compute.
- Cost if wrong: 3 types.

## 30. Unmapped: azurerm "Confidential Ledger"

- Question: Map Confidential Ledger (2 types)?
- Call: Leave unmapped.
- Rejected: database (it stores records); security (it is tamper-evident).
- Why: It is equally both, and picking one would be arbitrary.
- Cost if wrong: 2 types.

## 31. Unmapped: azurerm "Databox Edge"

- Question: Map Databox Edge (azurerm_databox_edge_device: 2 types)?
- Call: Leave unmapped.
- Rejected: iot; compute; storage; migration.
- Why: Azure Stack Edge devices do edge compute, storage gateway and data transfer. The label does not say which a configuration uses.
- Cost if wrong: 2 types.

## 32. Unmapped: azurerm "Extended Location"

- Question: Map Extended Location (custom locations: 2 types)?
- Call: Leave unmapped.
- Rejected: management, with the other Arc labels.
- Why: A custom location is a deployment target that other resources reference. It does not manage anything itself, and its meaning depends on what is deployed into it.
- Cost if wrong: 2 types.

## 33. Unmapped: azurerm "Fluid Relay"

- Question: Map Fluid Relay (azurerm_fluid_relay_server: 1 type)?
- Call: Leave unmapped.
- Rejected: messaging.
- Why: It is a real-time collaboration backend, not a queue or event bus.
- Cost if wrong: 1 type.

## 34. Unmapped: azurerm "Graph Services"

- Question: Map Graph Services (azurerm_graph_services_account: 2 types)?
- Call: Leave unmapped.
- Rejected: identity (it involves Microsoft Graph); management (it is a billing hookup).
- Why: The account only links Microsoft Graph API metered billing to a subscription. No drawer fits.
- Cost if wrong: 2 types.

## 35. Unmapped: azurerm "Healthcare"

- Question: Map Healthcare (FHIR, DICOM and MedTech services and workspaces: 11 types)?
- Call: Leave unmapped.
- Rejected: database (FHIR is a data store); analytics; iot (MedTech ingests device data).
- Why: It is an industry vertical that spans three drawers. Placing it in one would mislead.
- Cost if wrong: 11 types.

## 36. Unmapped: azurerm "Maps"

- Question: Map Maps (azurerm_maps_account and creator: 2 types)?
- Call: Leave unmapped.
- Rejected: analytics; iot.
- Why: It is a geospatial API service, and no drawer covers location services.
- Cost if wrong: 2 types.

## 37. Unmapped: azurerm "Search"

- Question: Map Search (azurerm_search_service and shared private link: 3 types)?
- Call: Leave unmapped.
- Rejected: ai (Microsoft now brands it Azure AI Search); analytics; database.
- Why: The label is the legacy name, and the service is now used both for full-text search and as a vector store for AI. Either drawer is defensible, so neither is chosen.
- Cost if wrong: 3 types.

## 38. Unmapped: azurerm "Workloads"

- Question: Map Workloads (SAP virtual instances: 3 types)?
- Call: Leave unmapped.
- Rejected: compute; management.
- Why: SAP virtual instances deploy and register whole SAP systems: VMs, storage, networking and an application layer. It is a workload, not one drawer's concern.
- Cost if wrong: 3 types.

## 39. How providers are named on the classifier commands

- Question: How does `-Provider` resolve on New-TerraformClassifier versus Get-TerraformClassifier and Get-TerraformClassifierFinding?
- Call: New-TerraformClassifier resolves a wildcard through the registry cache (exactly one match, as Update-TerraformProviderDocCache does), then reads the local caches. Get-TerraformClassifier and Get-TerraformClassifierFinding match patterns by shape against the classifier files they find, as Get-TerraformSchemaCache does, and accept several matches.
- Rejected: Registry resolution for the readers.
- Why: The readers list local files, so matching what is on disk is the natural behaviour. Generation names one provider to build.
- Cost if wrong: `New-TerraformClassifier -Provider 'azure*'` errors on an ambiguous match, while `Get-TerraformClassifier 'azure*'` returns several.

## 40. The map is enforced, not only linted

- Question: Is the map lint only a test, or is it enforced at run time?
- Call: Both. New-TerraformClassifier stops before reading anything if the map has a row with no reason or subcategory, a drawer not in drawers.json, a row targeting unclassified, a bad provider, addedOn or addedBy, or a repeated provider and subcategory. Pester's 'Classifiers' Describe lints the bundled map with the same check, plus its own empty-reason check on the raw JSON.
- Rejected: A test-only lint.
- Why: A custom map passed with -MapPath never goes through the repo's tests.
- Cost if wrong: A half-finished custom map cannot be used until every row has a reason, which is intended.

## 41. Grading the drawer list against the subcategory survey

- Question: Entry 1 fixed twenty drawers from three providers (azurerm, azuredevops, vsphere). Does the doc-label survey of the bundled set (the registry's 34 official providers plus microsoft/azuredevops and vmware/vsphere) support each one, and do labels shared by three or more providers lack a drawer? Keep, rename, add or drop? Does API Management get a drawer?
- Evidence: `dist/survey/subcategories.json` from Invoke-Build HarvestBundleDocs on 2026-10-07 (bundled registry cache harvested 2026-10-07T02:55:12Z): 36 providers, 14,686 pages, 661 distinct labels, 893 rows. Only 11 providers publish labels at all: aws (260), google and google-beta (181 each, the same list), azurerm (112), ibm (56), kubernetes (24), azuread (17), hcp (12), vsphere (9), azurestack (8), turbonomic (5). The other 25 label nothing (awscc's 4,521 pages, vault's 269, tfe's 117 among them). Because google-beta repeats google and azuread/azurestack share azurerm's vocabulary, support is counted in independent families as well as providers. Each label was assigned to at most one drawer by a keyword probe (first match in a fixed priority order). The probe is evidence for the list, never a map row; 264 of 865 labelled rows matched no pattern, mostly vendor products (AppStream, Chronicle, Firebase, Satellite).
- Support per drawer (families; providers; labels; pages):
  - network: 7 (aws, azure, google, hcp, ibm, kubernetes, vsphere); 9; 24; 916. Keep.
  - compute: 6 (aws, azure, google, ibm, kubernetes, vsphere); 8; 26; 964. Keep.
  - storage: 6 (aws, azure, google, ibm, kubernetes, vsphere); 8; 32; 470. Keep.
  - database: 4 (aws, azure, google, ibm); 5; 32; 457. Keep.
  - identity: 5 (aws, azure, google, hcp, ibm); 7; 36; 538. Keep.
  - security: 7 (aws, azure, google, hcp, ibm, kubernetes, vsphere); 9; 42; 636. Keep.
  - messaging: 4 (aws, azure, google, ibm); 5; 22; 360. Keep.
  - observability: 4 (aws, azure, google, ibm); 5; 25; 286. Keep.
  - management: 6 (aws, azure, google, ibm, kubernetes, vsphere); 9; 50; 449. Keep. The broadest drawer, but every family has billing, accounts, projects or policy labels that belong nowhere else.
  - devops: 3 (aws, azure, google); 4; 21; 184. Keep. AWS Code*, Google Cloud Build/Deploy/Artifact Registry, azurerm Dev Center/Load Test/Chaos Studio; azuredevops is all devops by prefix (entry 43).
  - containers: 5 (aws, azure, google, ibm, turbonomic); 6; 14; 216. Keep.
  - serverless: 3 (aws, google, ibm); 4; 14; 135. Keep. Lambda, Cloud Functions, Cloud Run, Code Engine, IBM Functions. After entry 42 azurerm puts nothing here: its function apps are compute (entry 14).
  - dns: 4 (aws, azure, google, ibm); 7; 13; 156. Keep.
  - cdn: 3 (aws, azure, ibm); 3; 4; 141. Keep. Few labels, but CloudFront, CDN and IBM Internet Services are large.
  - analytics: 3 (aws, azure, google); 4; 48; 630. Keep.
  - ai: 3 (aws, azure, google); 4; 22; 340. Keep.
  - iot: 2 (aws, azure); 2; 4; 52. Keep, the weakest. Google retired IoT Core, so only two families label IoT. Dropping it would break anyone filtering on it to save one row.
  - media: 3 (aws, azure, google); 4; 14; about 45 (the probe's "streaming" also caught Managed Streaming for Kafka and HCP Log Streaming, which belong elsewhere). Keep.
  - migration: 3 (aws, azure, google); 4; 5; 68. Keep.
  - unclassified: the fallback, not graded.
- Labels in three or more providers (9) and whether a current row places them:
  - Storage (azurerm, azurestack, vsphere): storage by the `*` row. Placed.
  - Service Networking (azurerm, google, google-beta): network for azurerm; network fits google.
  - Base (azuread, azurerm, azurestack): management for azurerm (entry 15); management fits the others.
  - Cloud IAM (google, google-beta, hcp): identity fits.
  - Cloud Platform (google, google-beta, hcp): management fits (projects, folders, organizations, service usage).
  - Container Registry (google, google-beta, ibm): containers fits.
  - License Manager (aws, google, google-beta): management fits (drawers.json lists licensing).
  - Agent Registry (aws, google, google-beta): ai fits (registries of AI agents).
  - API Gateway (aws, google, google-beta): no drawer fits. That is the one gap.
  No rows are added for these: google, aws, ibm, hcp and azurestack have docs but no cached schema, so they have no classifier to place types in, and a `*` row would decide for them without review (entry 22).
- Call: Keep all twenty drawers with their names. Add one: `integration`, for API gateways and API management, application and SaaS connectors, and integration workflows (iPaaS). Insert it after messaging in drawers.json, so `unclassified` stays last. That answers the API Management question entry 2 left open: yes, an integration drawer, because three families label it: aws (API Gateway, API Gateway V2, AppFlow, AppSync, EventBridge Pipes), azure (API Management, Connections, Logic App) and google (API Gateway, Apigee, Application Integration, Integration Connectors). They hold 266 pages, the largest block of labels with no home. Entry 42 moves the azurerm rows.
- Rejected: Renaming devops to "developer tools" (azuredevops and the AWS Code* family call it DevOps). Dropping iot (above). Dropping cdn or migration (three families each). A `desktop` drawer for AWS WorkSpaces/AppStream, azurerm Desktop Virtualization and Google Cloud Workstations: three families, but every one is virtual machines handed to users, which compute already describes. An `industry` drawer for Healthcare (azurerm, google): two families, and entry 35's reason (one vertical spanning three drawers) still holds. A `configuration` drawer for AWS AppConfig and azurerm/ibm App Configuration: two exact labels and 6 azurerm types, left unmapped as entry 28 records; worth another look if a third family labels it. Mapping integration into network or serverless: an API gateway is neither network plumbing nor per-execution compute.
- Why: The list was given for three providers. The survey shows it carries over to the large clouds: every drawer except iot has three or more families, and the only shared label with nowhere to go is integration. One added drawer is cheap (entry 1); renames and drops are not.
- Cost if wrong: integration is the 21st drawer; a view gains one row. If integration should have been folded into another drawer, 86 azurerm types move back with a superseding entry. The keyword probe can misplace a label at the edges (it put HCP Log Streaming in media), so the counts are approximate by a label or two per drawer; the conclusions do not rest on any single label.

## 42. integration drawer: API Management, Connections and Logic App move into it

- Question: With integration added (entry 41), where do azurerm "API Management", "Connections" and "Logic App" go?
- Call: All three map to integration. Supersedes 2 (no integration drawer), 27 (API Management unmapped) and 29 (Connections unmapped). Logic App moves out of serverless. The serverless description drops "workflows" and names serverless containers and state machines instead.
- Rejected: Leaving Logic App in serverless (entry 2's reason): it does run per trigger with no servers, but it is Azure's integration workflow product, and its connectors are the Connections label. Splitting them across two drawers would separate a workflow from the connectors it calls.
- Why: Rows map labels to what the label's types are for. API Management (64 types) and Connections (3) had no drawer only because integration did not exist.
- Cost if wrong: 86 azurerm types change drawer: 67 leave unclassified (azurerm unclassified falls from 101 to 34) and 19 leave serverless, which then holds no azurerm types.

## 43. Prefix rows: a second map source for providers with no labels

- Question: azuredevops publishes no subcategory labels (entry 10), so all 177 of its types were unclassified. How can it be drawered without hand-sorting types?
- Call: map rows gain an optional `source`. `subcategory` (the default) is the existing row kind. A `prefix` row names one provider address (never `*`) and its `subcategory` field holds a type prefix after the provider token: `git` for `azuredevops_git_*`. Subcategory rows win. A prefix row places only a type that has no label, meaning no doc page or an empty subcategory. A type whose label the map does not place stays `UnmappedSubcategory`, because the provider did say something about it and the map's silence is the finding. A type placed by a prefix row has no finding. Each classifier type records `source` (`subcategory`, `prefix`, or null when unclassified), and the file's top-level `source` is `subcategory,prefix` when any prefix row placed a type. A prefix row that matches no type in the provider's cached schema stops New-TerraformClassifier (`ClassifierMapInvalid`), and Pester checks the bundled map's prefix rows against the bundled classifiers.
- Rejected: A provider-wide default drawer (entry 10's "obvious next feature"): it would put azuredevops groups and users in devops. Per-type override rows, which would be hand-sorting 177 rows. Letting prefix rows override labels, which would let a prefix silently contradict what the provider published. `*` prefix rows: `git` means something different in every provider.
- Why: Type names are the one grouping every provider publishes. A prefix is a judgement about a family of types, like a label row is, and it stays reviewable in the map with a reason. Partly supersedes 10: azuredevops still publishes no labels, and the findings are gone because prefix rows now place every type.
- Cost if wrong: A new azuredevops type whose prefix has no row is `NoSubcategory` again, and a new type under an existing prefix lands in that prefix's drawer silently. The lint only catches prefixes that match nothing.

## 44. Prefixes match at underscore boundaries

- Question: Should prefix `git` match any type whose remainder starts with "git", or only `git` and `git_*`?
- Call: Only at underscore boundaries: the type without its provider token must equal the prefix or start with the prefix and `_`. The longest matching prefix wins. So `group` matches `azuredevops_group` and `azuredevops_group_membership` but not `azuredevops_groups`, which gets its own row.
- Rejected: Plain string prefixes, which would let `git` catch a future `github_*` type and `service` catch `serviceendpoint_*`, the fuzzy matching entry 5 rejects for labels. Folding plurals, which is a rule about English, not about the provider.
- Why: Predictable matching, the same reason as entry 5. Plural data sources (`groups`, `projects`, `teams`, `users`) are few and stable.
- Cost if wrong: More rows than plain prefixes would need: azuredevops has 41 prefix rows where plain prefixes would need 33. The task expected 10 to 20; its 177 types (154 distinct names) start with 41 distinct leading tokens, so no prefix scheme gets near 20 without leaving families unclassified.

## 45. azuredevops permissions go with the object they guard; security namespaces are identity

- Question: azuredevops has a `*_permissions` type for most objects (`git_permissions`, `build_definition_permissions`, `area_permissions`, `library_permissions`, `tagging_permissions`, ...) and a generic ACL layer (`security_namespace*`, `security_permissions`, `securityrole_*`). Identity, or the object's drawer?
- Call: A permissions type takes its object's drawer through the object's prefix (`git_permissions` is devops with `git`). The standalone ones get their own rows in devops: `library_permissions` (the pipeline library) and `tagging_permissions` (project tags). The generic ACL layer (`security`, `securityrole`) is identity, as azurerm's "Authorization" role assignments are.
- Rejected: Every `*_permissions` type in identity, which would need a suffix match (a new map feature) or one row per type.
- Why: Rows map families, and the family is the object. Someone collapsing a view to devops expects a repository's permissions inside the repository's drawer. The generic namespaces have no object, only principals and access.
- Cost if wrong: An identity view of azuredevops misses the 14 per-object permission types that sit in devops; only `security_permissions` is identity.

## 46. Individual azuredevops prefix calls

- Question: Where do the azuredevops families that could go two ways belong?
- Call:
  - `dashboard` is devops: project dashboards of Boards and pipeline widgets, not infrastructure monitoring (observability).
  - `servicehook` is devops: hooks that send project events to web hooks and storage queues. They belong to the project's delivery plumbing. Integration (entry 41) was weighed and rejected, because these hooks only serve Azure DevOps events.
  - `storage_key` is identity: the data source resolves a graph subject descriptor to its storage key, an identity id. It is not storage.
  - `team` and `teams` are identity: teams are groups of people in a project, with members and administrators. Their area and iteration settings come through the separate `area` and `iteration` families.
  - `client_config` is management, as azurerm's client config sits under Base (entry 15).
  - `extension`, `elastic_pool`, `deployment_group`, `environment`, `check`, `feed`, `wiki`, `area`, `iteration` and every `workitem*` family are devops: they are Azure DevOps's own Boards, Pipelines, Artifacts and Repos.
- Rejected: observability for dashboard; messaging for servicehook; storage for storage_key; devops for team.
- Why: Each call follows what the type does, not what its name suggests.
- Cost if wrong: dashboard 1, servicehook 3, storage_key 1, team and teams 5, client_config 1 type.

## 47. Drawer names follow semver

- Question: drawers.json is a public vocabulary: views, filters and agent prompts select on `Drawer -eq 'network'`. What kind of release may change it?
- Call: Adding a drawer, adding or re-pointing map rows, and refreshing classifiers from newer schemas or docs are minor (0.x.0 or x.y.0). Renaming or removing a drawer is major: it needs the psd1 ModuleVersion major above the previous release's. Pester ("drawers are semver-safe") reads drawers.json from the newest `v<x.y.z>` git tag below the psd1 version (falling back to `tests/fixtures/classifiers/drawers.<version>.json` when git or the tag is missing), passes added drawers, and fails a removed or renamed name unless the major went up. A rename counts as a removal plus an addition.
- Rejected: Allowing renames in a minor release with an alias table (the classifier files and every consumer would need to read it, and an alias is a rename nobody sees); treating drawers.json as internal (ONTOLOGY.md lists it as the drawer term's data file, and agents branch on its names); checking only the drawer count (a rename keeps the count).
- Why: Entry 1 already said renaming or removing a drawer breaks anyone filtering on the old name. The gate makes that cost visible at release time instead of in someone's view.
- Cost if wrong: Under 1.0.0 every major bump is 0 to 1, so the first rename forces 1.0.0. If that is too heavy, a superseding entry can make 0.x minors carry renames with the test's major check moved to minor, and the fixture fallback keeps working without git.

## 48. Classifier precedence for the same provider version

- Question: Should a newer bundled classifier beat an older user-folder classifier for the same provider version? The 0.13.0 release left classifiers generated under 0.12.0 in `$env:LOCALAPPDATA\TerraformGraph\classifiers` shadowing the bundled ones at the same versions, so lookups used files built from the 0.12.0 map (no integration drawer, no prefix rows) with nothing on screen to say so.
- Call: Entry 4 still picks the version: with no `-Version`, the first folder in lookup order that holds the provider picks its newest version there. When more than one folder holds that same version, a file from `-ClassifierPath` always wins (it is explicit). Otherwise the file whose `mapVersion` equals the bundled map.json's wins; among those, or when none matches, the newer `generatedOn` wins; then lookup order. Every losing file whose mapVersion or generatedOn differs from the winner's gets a warning naming its path and the fix (delete the user file, or `Invoke-Build BuildClassifier -Provider <address>` to promote a newer user file into the module). `Get-TerraformClassifier -Shadowed` lists each provider version present in more than one location, with the winning location, path and reason. Supersedes entry 4's "with -Version, the first file at that version wins whatever folder it is in".
- Rejected: Bundled always beats user for the same version (a user who regenerates with their own map would be ignored with no way to win but `-ClassifierPath`); user always wins (the 0.13.0 problem); newest generatedOn alone (a classifier regenerated yesterday from an old map would beat today's bundled one built from the current map); deleting stale user files on import (the module never deletes user data).
- Why: mapVersion says which map a file was built from, and the bundled map is the one this module release documents and tests. generatedOn breaks ties between files built from the same map. The warning turns a silent shadow into a one-line fix.
- Cost if wrong: A user who deliberately keeps an older-map classifier at the same version as a bundled one now loses to the bundled one and sees a warning; `-ClassifierPath` restores their choice. Reading generatedOn and mapVersion costs nothing extra: they are in the first 1 KB the lookup already reads.

## 49. Correction to entry 45's count: 13 permission types sit in devops

- Question: Entry 45's "Cost if wrong" says an identity view of azuredevops misses "the 14 per-object permission types that sit in devops". Is 14 right?
- Call: No. The azuredevops 1.16.0 classifier has 14 `*_permissions` types: 13 are in devops (area, build_definition, build_folder, git, iteration, library, project, serviceendpoint, servicehook, tagging, variable_group, workitemquery, workitemtrackingprocess_process) and 1, `azuredevops_security_permissions`, is in identity. Entry 45's call stands; only its count changes: an identity view misses 13. Supersedes entry 45's count, not its call.
- Rejected: Editing entry 45 in place (this file is append-only).
- Why: The 0.14.0 audit counted the classifier's types by drawer; the 14 counted every `_permissions` type, the identity one included.
- Cost if wrong: None to the map or the classifiers; this is a record correction.

## 50. Every terminating error goes through one helper, and the test reads the code

- Question: 0.14.0 said every terminating error names its fix, but eight bare `throw "..."` statements reached users with the message text as their FullyQualifiedErrorId, four of them naming no command, and the Pester list only found the ids built with `[ErrorRecord]::new`. How is the contract made checkable?
- Call: Every terminating error is raised by private `Stop-TerraformGraphCommand -Id -Message -Category -Target` (optional `-ExceptionType`, `-InnerException`). It calls the calling command's `$PSCmdlet.ThrowTerminatingError`, so ids read `<Id>,<command>` as before; a private helper whose caller catches and rewraps passes `-Throw`, because ThrowTerminatingError cannot be caught by the same command's own try/catch. The Pester test "names a documented fixing command for every terminating error id in the psm1" reads the psm1 AST and fails on: a Stop-TerraformGraphCommand `-Id` that is not a literal (or the `$($errorPrefix)` pack form); an id not in its list, or a listed id no longer raised; a `throw` with anything after it outside the helper and outside ValidateScript blocks; an `[ErrorRecord]::new` outside the helper and New-TerraformHclParseError (non-terminating); a ThrowTerminatingError outside the helper except `$PSCmdlet.ThrowTerminatingError($_)`, which passes on a record the helper raised; a user-facing literal message (no `-Throw`) that names no exported command, Invoke-Build, New-Item or terraform init. A missing bundle is `BundleNotFound` and a missing registry cache `RegistryCacheNotFound` in every command that reads them. New ids in 0.14.1: ParserUnavailable, TerraformNotOnPath, TerraformInitFailed, TerraformVersionUnreadable, TerraformProvidersSchemaFailed, ProviderAddressInvalid, ProviderVersionInvalid, RegistryRequestFailed, PackAssetNotFound (42 in all).
- Rejected: Keeping hand-written ThrowTerminatingError blocks and teaching the test more construction styles (39 copies, and every new style is a new hole); `throw [ErrorRecord]` everywhere (ids would lose the `,<command>` suffix callers already match on); checking messages by running every error path (most need terraform, the network or a broken cache).
- Why: One construction style is one thing to scan. The test now fails on the exact pattern that made the 0.14.0 claim untrue.
- Cost if wrong: A message assembled at runtime (`-Message $_.Exception.Message`, `-Message $reason`) is not checked for a fix command; its text comes from an inner `-Throw` site, whose literal is not checked either. ValidateScript messages keep PowerShell's ParameterArgumentValidationError id.

## 51. Test-TerraformGraphBundle -Scope, and Repo is the release gate

- Question: `Invoke-Build CheckBundle` (Test-TerraformGraphBundle -Strict) passed with 89 Fresh rows on the author's machine and reported 39 Missing and 1 Stale on a machine with empty caches: it certified the author's `$env:LOCALAPPDATA`, not the repository. What should the release gate certify?
- Call: `-Scope Machine|Repo`, default Machine (the 0.14.0 behaviour). Repo reads only the bundle's own folder (the registry.json beside it, never the user registry cache), the module's bundled classifiers and map.json, and `-DistPath`. It emits no docs or schema rows (those live only in user caches), and in the sources row it leaves the schemas `lastPulled` unchecked (a schema cache file time). Its rows are therefore identical with any user cache or none (a Pester test proves it). CheckBundle runs `-Scope Repo -Strict`. On the shipped data: Repo 50 rows, all Fresh; Machine 89.
- Rejected: Changing the default to Repo (a user checking their own bundle copy wants their caches checked); dropping the docs rows (they are the useful part for a user's copy); shipping the 33 providers' docs as packs to make Machine pass anywhere (about 14 MB of docs the release does not need, and a data decision outside this fix).
- Why: A gate that passes only on one machine is a statement about that machine. What a clean clone holds is what a release ships.
- Cost if wrong: The release gate no longer notices that the author's docs cache is behind the bundle entries; `Test-TerraformGraphBundle -Scope Machine` still shows it, and HarvestBundleDocs rewrites the entries from the caches anyway. dist/schema-packs is read when present but is not in a clean clone, so pack rows appear only where BuildSchemaPack ran.

## 52. The two doors are banners, not a ban

- Question: Pester "keeps the two doors" failed if `ontolog` appeared anywhere in README.md after line 1, and the readme skill forbade any later mention. Does the split between README.md (sysadmin door) and ONTOLOGY.md (agent and ontology door) need that ban to hold?
- Call: No. The test checks only the doors: README line 1 is a `>` blockquote linking ONTOLOGY.md, ONTOLOGY.md's first non-blank line is a `>` blockquote and its second links README.md. Each doc opens with a banner pointing at the other; further mentions are allowed. The readme and ontology-doc skills state the same rule. Where the explanation lives does not change: the agent story, terminology and facts and opinions stay in ONTOLOGY.md.
- Rejected: Keeping the word ban (it fails a README sentence that merely names ONTOLOGY.md where a reader needs it, such as a classifier or Id section, and a word match cannot tell a pointer from a duplicated explanation); dropping the test (the banners are what make each door findable from the other).
- Why: What the test can check reliably is the two banners. Whether a README paragraph has turned into ontology prose is a review judgement, which the readme skill's "Do not add ontology prose" line keeps.
- Cost if wrong: Ontology explanation can creep into README.md without a test failing; the readme skill and review are the only guard.
