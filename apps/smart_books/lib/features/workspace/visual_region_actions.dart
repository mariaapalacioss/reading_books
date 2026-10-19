/// Acciones multimodales sobre una región del PDF (texto + imagen de recorte).
enum VisualRegionAction {
  explain,
  createQuestion,
  saveForReview,
  addNote,
}

extension VisualRegionActionX on VisualRegionAction {
  String get label => switch (this) {
    VisualRegionAction.explain => 'Explicar',
    VisualRegionAction.createQuestion => 'Crear pregunta',
    VisualRegionAction.saveForReview => 'Guardar en Repaso',
    VisualRegionAction.addNote => 'Añadir nota',
  };
}

/// Metadatos opcionales para clasificar la región (gráfico, tabla, fórmula…).
enum VisualRegionKind {
  image,
  chart,
  table,
  formula,
  blueprint,
  screenshot,
  diagram,
  generic,
}

extension VisualRegionKindX on VisualRegionKind {
  String get label => switch (this) {
    VisualRegionKind.image => 'Imagen',
    VisualRegionKind.chart => 'Gráfico',
    VisualRegionKind.table => 'Tabla',
    VisualRegionKind.formula => 'Fórmula',
    VisualRegionKind.blueprint => 'Plano',
    VisualRegionKind.screenshot => 'Captura',
    VisualRegionKind.diagram => 'Diagrama',
    VisualRegionKind.generic => 'Región',
  };

  String get metadataValue => name;
}

Map<String, dynamic> visualRegionMetadata({
  required VisualRegionKind kind,
  VisualRegionAction? lastAction,
}) => {
  'visual_region_kind': kind.metadataValue,
  if (lastAction != null) 'last_action': lastAction.name,
};
