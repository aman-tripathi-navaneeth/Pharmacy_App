import 'package:flutter/material.dart';

enum LegalDocument { terms, privacy }

class LegalInformationScreen extends StatelessWidget {
  const LegalInformationScreen({super.key, required this.document});

  final LegalDocument document;

  static const _termsSections = <(String, String)>[
    (
      'Using the application',
      'MediManage provides pharmacy operators and their authorized team members with tools for shop administration, inventory, suppliers, sales, customer accounts, prescriptions, reports, and related workflows. Use the application only for lawful business purposes and only with an account and permissions granted to you.',
    ),
    (
      'Accounts and access',
      'Keep your sign-in details private, use a unique password, and notify your pharmacy administrator if you suspect unauthorized access. You are responsible for activity performed through your account. Administrators should assign access only to people who need it and remove access when it is no longer appropriate.',
    ),
    (
      'Records and regulated work',
      'You are responsible for entering accurate information, checking bills and OCR suggestions, maintaining appropriate records and backups, and following the laws and professional requirements that apply to your pharmacy. The application is an administrative tool; it does not provide medical advice, diagnose conditions, or replace a pharmacist’s professional judgment. Verify prescriptions and dispensing decisions through your approved procedures.',
    ),
    (
      'Acceptable use',
      'Do not access another shop’s information without authorization, misuse customer or patient information, interfere with the service, or use the application to break the law. Do not rely on the application as the only copy of records required for your business or by law.',
    ),
    (
      'Availability and changes',
      'Features depend on the deployment, configuration, network, and services enabled by the operator. The operator may update, suspend, or discontinue features to maintain or protect the service. Keep independent copies of records where your business or applicable rules require them.',
    ),
    (
      'Questions and updates',
      'For account access, data, or service questions, contact the pharmacy owner or the administrator responsible for your deployment. The organization operating the deployment should review and adapt these terms for its business, jurisdiction, and any separate agreements before production use.',
    ),
  ];

  static const _privacySections = <(String, String)>[
    (
      'Information the application handles',
      'Depending on the features you use, the application may handle account names, contact details, password hashes, account status and roles, session and sign-in activity, shop profiles and licence details, and profile or payment configuration such as a UPI identifier.',
    ),
    (
      'Business, customer, and prescription records',
      'The application can process product and batch details, stock movements, supplier and purchase records, sales and bill line items, payment methods and amounts, customer contact and balance information, and prescription or patient information entered by authorized users. Do not enter information that is not needed for the pharmacy workflow.',
    ),
    (
      'Images, notifications, and support',
      'A user may upload a profile image or submit a bill image for OCR processing when that feature is enabled. OCR results are suggestions and must be checked by a person. The application may record in-app notifications, issue reports, email delivery history, and audit events needed for operations and troubleshooting. Email is sent only when the deployment has configured an email service; external messaging integrations depend on deployment configuration.',
    ),
    (
      'How information is used',
      'Information is used to authenticate users, enforce role-based access, operate shop and pharmacy workflows, prepare reports, process OCR requests, deliver configured notifications, investigate support issues, and protect the service. Data should be accessed only by authorized users for these purposes.',
    ),
    (
      'Storage and service providers',
      'Application records are stored in the PostgreSQL database configured by the organization operating the deployment. The operator controls the hosting environment, backups, access, retention, and deletion. Configured email, OCR, or messaging services may process the information needed to provide those features; the operator should review each provider and its settings before enabling it. This application does not make a blanket guarantee about a deployment’s encryption, hosting location, or provider practices.',
    ),
    (
      'Retention and your choices',
      'The organization operating the deployment determines retention periods and handles requests to access, correct, export, or delete information, subject to its legal and record-keeping duties. Contact your pharmacy owner or deployment administrator for those requests. Avoid sharing patient or customer information in support messages unless it is necessary.',
    ),
    (
      'Protecting sensitive information',
      'Use individual accounts, limit permissions, secure devices and network access, and follow your organization’s incident-reporting process. Pharmacy operators are responsible for establishing a lawful basis for handling customer and health information and for meeting applicable privacy, pharmacy, and record-retention requirements.',
    ),
    (
      'Policy owner and review',
      'The pharmacy or organization operating this deployment is responsible for its data practices and for adapting this notice to its jurisdiction, providers, and actual configuration. Contact that organization’s administrator with privacy questions. These pages are general product information, not legal advice.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isTerms = document == LegalDocument.terms;
    final title = isTerms ? 'Terms of Use' : 'Privacy Policy';
    final sections = isTerms ? _termsSections : _privacySections;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Text(
                  isTerms
                      ? 'Rules for using MediManage'
                      : 'How pharmacy and account information is handled',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF173B3A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'These pages describe the application’s intended use and data flows. The organization operating this deployment is responsible for reviewing them against its actual configuration and applicable requirements.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(height: 1.5, color: const Color(0xFF475569)),
                ),
                const SizedBox(height: 16),
                for (final (heading, content) in sections)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(content, style: const TextStyle(height: 1.5)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
