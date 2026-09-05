# Pitch — SGJ2026 · "Fragments"

## 1. Dato de interés (hook)
En la guerra real, la mayoría de bajas no las causa el impacto, sino la metralla que vuela: **son los fragmentos los que matan, no el proyectil**. En este juego, los fragmentos devuelven la jugada: el enemigo *es* cristal y mineral.

## 2. Equipo y juego
**Red Square** presenta **Blackstone Protocol** : un juego de acción táctica de tanques para PC, hecho en Godot 4.4 para Sanda Game Jam 2026 bajo el tema **FRAGMENTS**.

## 3. Concepto
Conduces un tanque sobre un **mundo abierto** de terreno irregular y hostil (en la versión final). Tus enemigos están hechos de fragmentos de cristal y mineral: al romperlos se desmoronan en esquirlas que pueden servirte de cobertura, dañarte o incluso reagruparse. Todo, disparo, manejo y física, gira alrededor de cómo se rompen y dispersan los fragmentos.

## 4. Referencias principales
- **Death Stranding** — lenguaje visual y estilo del vehículo
- **War Thunder / Tyr** — peso del manejo y de la torreta
- **SpinTires / BeamNG en vehículo** — física de suspensión realista sobre terreno
- **The Witness / Cristales** — lenguaje visual de minerales y cristales

## 5. Público objetivo
Jugadores de acción centrada en vehículos y de juegos tácticos ligeros (PC/Linux), fanáticos de física arcade-realista y de juegos jam con gancho visual claro. Edad 12+, sesiones cortas.

## 6. Puntos Únicos de Venta (USP)
- **La física es el enemigo:** suspensión VehicleBody3D real (8 ruedas con tracción), tiro y retroceso del cañón que empujan el casco — manejado, no arcade.
- **Enemigos de fragmentos reales:** los cristales se rompen, se separan y vuelven a unirse según cómo les dispares — el combate es también geometría.
- **Terreno, no escenario:** usar lomas y huecos para cubrirse decide el combate antes que el reflejo.

## 7. Gameplay y mecánicas relevantes
- **Conducción:** W/S acelerar y reversa, A/D girar, ESPACIO freno de mano; la pendiente y el bajón roban tracción.
- **Puntería de torreta:** el ratón dirige yaw y pitch, con límites y giro realista que tienes que acompañar.
- **Cañón:** disparo con raycast (o proyectil) desde la boca del cañón; el retroceso impacta el casco.
- **Ciclo de combate:** reconocer el terreno → posicionarte → romper enemigos de cristal → gestionar las esquirlas que quedan.
- **Ya implementado:** movimiento, torreta, disparo, cámaras 1ª/3ª (tecla V), terreno (Terrain3D), menús y lore de introducción.
- **Por construir:** mundo abierto, IA de enemigos de cristal, objetivos y condiciones de victoria, HUD (vida/municiones), puntuación y pantalla final.

## 8. Call to action
Sube a la torreta, apunta donde el cristal se rompe en pedazos — y decide quién se queda con los fragmentos. **Prueba «_[Título]_» y dime qué es lo que estás dispuesto a romper.**