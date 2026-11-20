import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Reto: Localizador de Puntos de Interés
/// 1. Ubicación actual: centrar cámara en el usuario al iniciar.
/// 2. Marcador dinámico: crear pin al tocar cualquier punto del mapa.
/// 3. Distancia en vivo: mostrar metros entre usuario y destino.
/// 4. Dirección postal: desplegar calle y colonia mediante geocodificación.
class PantallaMapa extends StatefulWidget {
  const PantallaMapa({super.key});

  @override
  State<PantallaMapa> createState() => _PantallaMapaState();
}

class _PantallaMapaState extends State<PantallaMapa> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _posicionSub;

  Set<Marker> _marcadores = {};
  Position? _posicionUsuario;
  LatLng? _destino;
  double? _distanciaMetros;

  String? _calle;
  String? _colonia;
  bool _buscandoDireccion = false;
  String? _errorDireccion;

  String? _errorUbicacion;
  bool _listo = false;
  bool _centrado = false;
  int _contadorMarcadores = 0;
  int _consultaId = 0; // evita que una respuesta lenta pise a una reciente

  @override
  void initState() {
    super.initState();
    _iniciarUbicacion();
  }

  @override
  void dispose() {
    _posicionSub?.cancel(); // cancela el StreamSubscription
    _mapController?.dispose(); // libera el GoogleMapController
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // PASO 04 · Obtención de coordenadas en tiempo real
  // ---------------------------------------------------------------------
  Future<Position> obtenerUbicacion() async {
    // Hardware: verifica si el sensor GPS está encendido.
    bool activo = await Geolocator.isLocationServiceEnabled();
    if (!activo) return Future.error('GPS desactivado');

    // Runtime: solicita permiso explícito al usuario.
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return Future.error('Permiso de ubicación denegado');
    }

    // Precisión: LocationAccuracy.high para navegación.
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _iniciarUbicacion() async {
    setState(() {
      _listo = false;
      _centrado = false;
      _errorUbicacion = null;
    });
    try {
      final pos = await obtenerUbicacion();
      if (!mounted) return;
      setState(() {
        _posicionUsuario = pos;
        _listo = true;
      });
      _centrarEnUsuario();

      // Lectura continua; distanceFilter de 10 m evita actualizaciones
      // redundantes y ahorra batería.
      await _posicionSub?.cancel();
      _posicionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (p) {
          if (!mounted) return;
          setState(() {
            _posicionUsuario = p;
            _recalcularDistancia();
          });
        },
        onError: (Object e) => _mensaje('Error de ubicación: $e'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorUbicacion = e.toString();
        _listo = true; // se muestra el mapa en UTXJ con el aviso del error
      });
    }
  }

  /// Requerimiento 1: centrar la cámara en el usuario al iniciar.
  void _centrarEnUsuario() {
    final pos = _posicionUsuario;
    final ctrl = _mapController;
    if (pos == null || ctrl == null || _centrado) return;
    _centrado = true;
    ctrl.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
    );
  }

  // ---------------------------------------------------------------------
  // PASO 06 · Cálculo de distancia y geocodificación inversa
  // ---------------------------------------------------------------------
  void _recalcularDistancia() {
    final pos = _posicionUsuario;
    final destino = _destino;
    if (pos == null || destino == null) {
      _distanciaMetros = null;
      return;
    }
    double metros = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      destino.latitude,
      destino.longitude,
    );
    _distanciaMetros = metros;
  }

  // ---------------------------------------------------------------------
  // PASO 05 · Marcadores (onTap) con InfoWindow
  // ---------------------------------------------------------------------
  Future<void> _agregarMarcador(LatLng punto) async {
    final id = ++_consultaId;
    final numero = ++_contadorMarcadores;
    final markerId = MarkerId('punto_$numero');

    setState(() {
      _marcadores = {
        ..._marcadores,
        Marker(
          markerId: markerId,
          position: punto,
          infoWindow: InfoWindow(
            title: 'Punto $numero',
            snippet: 'Consultando dirección...',
          ),
        ),
      };
      _destino = punto;
      _calle = null;
      _colonia = null;
      _errorDireccion = null;
      _buscandoDireccion = true;
      _recalcularDistancia();
    });

    try {
      List<Placemark> lugares =
          await placemarkFromCoordinates(punto.latitude, punto.longitude);
      String calle = lugares.first.street ?? '';
      String colonia = lugares.first.subLocality ?? '';

      if (!mounted || id != _consultaId) return;
      setState(() {
        _calle = calle;
        _colonia = colonia;
        _buscandoDireccion = false;
        _marcadores = {
          ..._marcadores.where((m) => m.markerId != markerId),
          Marker(
            markerId: markerId,
            position: punto,
            infoWindow: InfoWindow(
              title: 'Punto $numero',
              snippet: '$calle, $colonia',
            ),
          ),
        };
      });
    } catch (_) {
      if (!mounted || id != _consultaId) return;
      setState(() {
        _errorDireccion = 'No se pudo obtener la dirección.';
        _buscandoDireccion = false;
      });
    }
  }

  void _limpiarMarcadores() {
    _consultaId++;
    setState(() {
      _marcadores = {};
      _destino = null;
      _distanciaMetros = null;
      _calle = null;
      _colonia = null;
      _errorDireccion = null;
      _buscandoDireccion = false;
    });
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  String _formatoDistancia(double metros) {
    if (metros >= 1000) return '${(metros / 1000).toStringAsFixed(2)} km';
    return '${metros.toStringAsFixed(0)} m';
  }

  String _o(String? valor) =>
      (valor == null || valor.trim().isEmpty) ? 'No disponible' : valor;

  // ---------------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Localizador de Puntos de Interés')),
      body: !_listo
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Obteniendo ubicación...'),
                ],
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(20.2756, -97.9611), // UTXJ
                    zoom: 15.5,
                  ),
                  myLocationEnabled: true,
                  markers: _marcadores,
                  padding: const EdgeInsets.only(bottom: 200),
                  onMapCreated: (ctrl) {
                    _mapController = ctrl;
                    _centrarEnUsuario();
                  },
                  onTap: (LatLng punto) => _agregarMarcador(punto),
                ),
                if (_errorUbicacion != null)
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: _avisoError(),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: SafeArea(child: _panelInfo()),
                ),
              ],
            ),
    );
  }

  Widget _avisoError() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.location_off),
            const SizedBox(width: 8),
            Expanded(child: Text(_errorUbicacion ?? '')),
            TextButton(
              onPressed: _iniciarUbicacion,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelInfo() {
    final estilo = Theme.of(context).textTheme.bodyMedium;
    final pos = _posicionUsuario;
    final destino = _destino;

    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.my_location, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pos == null
                        ? 'Ubicación no disponible'
                        : 'Tú: ${pos.latitude.toStringAsFixed(5)}, '
                            '${pos.longitude.toStringAsFixed(5)} '
                            '(±${pos.accuracy.round()} m)',
                    style: estilo,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (destino == null)
              Text(
                'Toca cualquier punto del mapa para crear un marcador.',
                style: estilo,
              )
            else ...[
              Row(
                children: [
                  const Icon(Icons.place, size: 18, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Destino: ${destino.latitude.toStringAsFixed(5)}, '
                      '${destino.longitude.toStringAsFixed(5)}',
                      style: estilo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.straighten, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _distanciaMetros == null
                        ? 'Distancia: sin ubicación del usuario'
                        : 'Distancia: ${_formatoDistancia(_distanciaMetros!)}',
                    style: estilo?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_buscandoDireccion)
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Consultando dirección...'),
                  ],
                )
              else if (_errorDireccion != null)
                Text(_errorDireccion!, style: estilo)
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.home_work_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Calle: ${_o(_calle)}', style: estilo),
                          Text('Colonia: ${_o(_colonia)}', style: estilo),
                        ],
                      ),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _limpiarMarcadores,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Limpiar marcadores'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}