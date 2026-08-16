// lib/server/routes/stock_routes.dart
// Stock Items + Suppliers API routes (mirrors payments_routes.dart /
// expenses_routes.dart). Two route classes since remote_data_source.dart
// already targets two distinct URL prefixes: /api/stock-items/ and
// /api/suppliers/.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';
import '../auth_middleware.dart';

Response _ok(dynamic body) =>
    Response.ok(jsonEncode(body), headers: {'Content-Type': 'application/json'});

Response _badRequest(String message) => Response(400,
    body: jsonEncode({'error': message}), headers: {'Content-Type': 'application/json'});

Response _serverError(String message, Object e) => Response.internalServerError(
    body: jsonEncode({'error': '$message: $e'}), headers: {'Content-Type': 'application/json'});

class StockItemsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.post('/', _createStockItem);
    router.get('/', _getStockItems);
    router.get('/low-stock', _getLowStockItems);
    router.get('/parents', _getParentItems);
    router.get('/parents/<parentId>/children', _getChildItems);
    router.post('/validate-parent', _canSetAsParent);
    router.get('/<id>', _getStockItemById);
    router.put('/<id>', _updateStockItem);
    router.delete('/<id>', _deactivateStockItem);
    router.delete('/<id>/permanent', _deleteStockItem);
    router.get('/<id>/has-children', _hasChildItems);
    router.get('/<id>/movements', _getStockMovements);
    router.post('/<id>/adjust', _adjustStockQuantity);
    router.post('/<id>/restock', _restockItem);

    return router;
  }

  Future<void> _writeAuditLog(
    Request request, {
    required int entityId,
    required String action,
    Map<String, dynamic>? changes,
  }) async {
    final db = await _db.database;
    await db.insert('audit_log', {
      'entityType': 'stock_item',
      'entityId': entityId,
      'action': action,
      'changes': changes != null ? jsonEncode(changes) : null,
      'userId': getUserIdFromRequest(request),
      'username': getUsernameFromRequest(request) ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _createStockItem(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = await _db.insertStockItem(data);

      final item = await _db.getStockItemById(id);
      if (item != null) {
        await _writeAuditLog(request, entityId: id, action: 'create', changes: item);
      }

      return _ok({'success': true, 'id': id});
    } catch (e) {
      return _serverError('Failed to create stock item', e);
    }
  }

  Future<Response> _getStockItems(Request request) async {
    try {
      final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
      return _ok(await _db.getStockItems(includeInactive: includeInactive));
    } catch (e) {
      return _serverError('Failed to get stock items', e);
    }
  }

  Future<Response> _getStockItemById(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');
      return _ok(await _db.getStockItemById(itemId));
    } catch (e) {
      return _serverError('Failed to get stock item', e);
    }
  }

  Future<Response> _updateStockItem(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final oldRow = await _db.getStockItemById(itemId);

      await _db.updateStockItem(itemId, data);

      if (oldRow != null) {
        final diff = <String, dynamic>{};
        for (final key in data.keys) {
          if (oldRow[key] != data[key]) diff[key] = {'old': oldRow[key], 'new': data[key]};
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(request, entityId: itemId, action: 'update', changes: diff);
        }
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to update stock item', e);
    }
  }

  Future<Response> _deactivateStockItem(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');

      final oldRow = await _db.getStockItemById(itemId);
      await _db.deactivateStockItem(itemId);

      if (oldRow != null && oldRow['isActive'] != 0) {
        await _writeAuditLog(request, entityId: itemId, action: 'update', changes: {
          'isActive': {'old': oldRow['isActive'], 'new': 0},
        });
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to deactivate stock item', e);
    }
  }

  Future<Response> _deleteStockItem(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');

      final row = await _db.getStockItemById(itemId);
      await _db.deleteStockItem(itemId);

      if (row != null) {
        await _writeAuditLog(request, entityId: itemId, action: 'delete', changes: row);
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to delete stock item', e);
    }
  }

  Future<Response> _adjustStockQuantity(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      await _db.adjustStockQuantity(
        itemId,
        data['newQuantity'] as int,
        data['note'] as String,
        createdBy: data['createdBy'] as String?,
      );

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to adjust stock quantity', e);
    }
  }

  Future<Response> _restockItem(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      await _db.restockItem(
        itemId,
        quantityAdded: data['quantityAdded'] as int,
        supplier: data['supplier'] as String,
        invoiceNumber: data['invoiceNumber'] as String?,
        newCostPrice: (data['newCostPrice'] as num?)?.toDouble(),
        notes: data['notes'] as String?,
        createdBy: data['createdBy'] as String?,
      );

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to restock item', e);
    }
  }

  Future<Response> _getLowStockItems(Request request) async {
    try {
      return _ok(await _db.getLowStockItems());
    } catch (e) {
      return _serverError('Failed to get low stock items', e);
    }
  }

  Future<Response> _getParentItems(Request request) async {
    try {
      return _ok(await _db.getParentItems());
    } catch (e) {
      return _serverError('Failed to get parent items', e);
    }
  }

  Future<Response> _getChildItems(Request request, String parentId) async {
    try {
      final id = int.tryParse(parentId);
      if (id == null) return _badRequest('Invalid parent ID');
      return _ok(await _db.getChildItems(id));
    } catch (e) {
      return _serverError('Failed to get child items', e);
    }
  }

  Future<Response> _hasChildItems(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');
      return _ok({'hasChildren': await _db.hasChildItems(itemId)});
    } catch (e) {
      return _serverError('Failed to check child items', e);
    }
  }

  Future<Response> _canSetAsParent(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final valid = await _db.canSetAsParent(
        data['itemId'] as int,
        data['parentItemId'] as int?,
      );
      return _ok({'valid': valid});
    } catch (e) {
      return _serverError('Failed to validate parent', e);
    }
  }

  Future<Response> _getStockMovements(Request request, String id) async {
    try {
      final itemId = int.tryParse(id);
      if (itemId == null) return _badRequest('Invalid stock item ID');
      final params = request.url.queryParameters;
      return _ok(await _db.getStockMovements(
        itemId,
        startDate: params['startDate'],
        endDate: params['endDate'],
      ));
    } catch (e) {
      return _serverError('Failed to get stock movements', e);
    }
  }
}

class SuppliersRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.post('/', _createSupplier);
    router.get('/', _getSuppliers);
    router.get('/<id>', _getSupplierById);
    router.put('/<id>', _updateSupplier);
    router.post('/<id>/deactivate', _deactivateSupplier);
    router.delete('/<id>', _deleteSupplier);

    return router;
  }

  Future<void> _writeAuditLog(
    Request request, {
    required int entityId,
    required String action,
    Map<String, dynamic>? changes,
  }) async {
    final db = await _db.database;
    await db.insert('audit_log', {
      'entityType': 'supplier',
      'entityId': entityId,
      'action': action,
      'changes': changes != null ? jsonEncode(changes) : null,
      'userId': getUserIdFromRequest(request),
      'username': getUsernameFromRequest(request) ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _createSupplier(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = await _db.insertSupplier(data);

      final supplier = await _db.getSupplierById(id);
      if (supplier != null) {
        await _writeAuditLog(request, entityId: id, action: 'create', changes: supplier);
      }

      return _ok({'success': true, 'id': id});
    } catch (e) {
      return _serverError('Failed to create supplier', e);
    }
  }

  Future<Response> _getSuppliers(Request request) async {
    try {
      final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
      return _ok(await _db.getSuppliers(includeInactive: includeInactive));
    } catch (e) {
      return _serverError('Failed to get suppliers', e);
    }
  }

  Future<Response> _getSupplierById(Request request, String id) async {
    try {
      final supplierId = int.tryParse(id);
      if (supplierId == null) return _badRequest('Invalid supplier ID');
      return _ok({'supplier': await _db.getSupplierById(supplierId)});
    } catch (e) {
      return _serverError('Failed to get supplier', e);
    }
  }

  Future<Response> _updateSupplier(Request request, String id) async {
    try {
      final supplierId = int.tryParse(id);
      if (supplierId == null) return _badRequest('Invalid supplier ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final oldRow = await _db.getSupplierById(supplierId);

      final updated = await _db.updateSupplier(supplierId, data);

      if (oldRow != null) {
        final diff = <String, dynamic>{};
        for (final key in data.keys) {
          if (oldRow[key] != data[key]) diff[key] = {'old': oldRow[key], 'new': data[key]};
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(request, entityId: supplierId, action: 'update', changes: diff);
        }
      }

      return _ok({'updated': updated});
    } catch (e) {
      return _serverError('Failed to update supplier', e);
    }
  }

  Future<Response> _deactivateSupplier(Request request, String id) async {
    try {
      final supplierId = int.tryParse(id);
      if (supplierId == null) return _badRequest('Invalid supplier ID');

      final oldRow = await _db.getSupplierById(supplierId);
      final updated = await _db.deactivateSupplier(supplierId);

      if (oldRow != null && oldRow['isActive'] != 0) {
        await _writeAuditLog(request, entityId: supplierId, action: 'update', changes: {
          'isActive': {'old': oldRow['isActive'], 'new': 0},
        });
      }

      return _ok({'updated': updated});
    } catch (e) {
      return _serverError('Failed to deactivate supplier', e);
    }
  }

  Future<Response> _deleteSupplier(Request request, String id) async {
    try {
      final supplierId = int.tryParse(id);
      if (supplierId == null) return _badRequest('Invalid supplier ID');

      final row = await _db.getSupplierById(supplierId);
      await _db.deleteSupplier(supplierId);

      if (row != null) {
        await _writeAuditLog(request, entityId: supplierId, action: 'delete', changes: row);
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to delete supplier', e);
    }
  }
}
