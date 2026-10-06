import 'package:flutter/material.dart';
import '../../domain/models/asset_model.dart';

class AssetFormWidget extends StatefulWidget {
  final AssetModel? initialAsset;
  final void Function(String name, String description) onSave;

  const AssetFormWidget({
    super.key,
    this.initialAsset,
    required this.onSave,
  });

  @override
  State<AssetFormWidget> createState() => _AssetFormWidgetState();
}

class _AssetFormWidgetState extends State<AssetFormWidget> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialAsset?.name ?? '');
    _descController = TextEditingController(text: widget.initialAsset?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSave(_nameController.text.trim(), _descController.text.trim());
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initialAsset == null ? 'Criar Ativo' : 'Editar Ativo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('asset_form_name_field'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome do Ativo',
                border: OutlineInputBorder(),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Nome é obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('asset_form_desc_field'),
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Descrição é obrigatória' : null,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('asset_form_save_button'),
              onPressed: _submit,
              child: const Text('Salvar Instantâneo'),
            ),
          ],
        ),
      ),
    );
  }
}
