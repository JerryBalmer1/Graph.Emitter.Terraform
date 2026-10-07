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
