# Contexto del proyecto (para retomar en otra sesión)

## Qué es esto

**Núcleo IA**: una API de IA propia. Todos nuestros proyectos (Zuma primero) le hablan solo a
esto, nunca directo a DeepSeek, OpenAI o Google. Por detrás puede haber modelos locales o
modelos por API, y cambiarlos no toca el código de los proyectos.

## Por qué

1. **No depender de una sola empresa.** Si un proveedor sube precios o se cae, se cambia en un
   solo lugar.
2. **Privacidad.** La meta final es que los datos de los restaurantes no salgan del servidor,
   igual que el argumento que vende Snowflake.
3. **Reutilizar.** Cada proyecto nuevo hereda gateway, medición de uso, límites y logs.
4. **Venderlo después.** Lo que se construye para uso propio puede ofrecerse a terceros.

## Decisiones tomadas

| Tema | Decisión |
|---|---|
| Motor del gateway | LiteLLM (open source, API compatible con OpenAI) |
| Nombres de modelo | `zuma-rapido`, `zuma-chat`, `zuma-vision`. Los proyectos solo conocen estos |
| Chat de pruebas | Página propia en `chat/index.html`. Open WebUI se descartó: pesado y se colgaba |
| Modelos locales | Ollama en el host, no en Docker |
| Servidor de producción | vLLM sobre GPU, porque Ollama no sirve para muchas peticiones a la vez |
| GPU elegida | RTX A6000 48 GB en RunPod (~0,33 USD/h Community, ~0,53 USD/h Secure) |
| Enrutador | Por reglas + escalada, NO un modelo que clasifique (ver abajo) |

## El enrutador (pendiente de construir)

El proyecto pediría un solo modelo, `zuma`, y Núcleo IA decide:

| Lo que llega | A dónde va |
|---|---|
| Trae imagen | `zuma-vision` |
| Trae herramientas (`tools`) | `zuma-chat` |
| Texto corto y simple | `zuma-rapido` |
| El rápido falla o no puede | Reintenta en `zuma-chat` (escalada) |

No se usa el enrutador automático de LiteLLM: está en beta y el semántico quedó descontinuado.
Serían unas 60 líneas en Python, del lado de Núcleo IA, no dentro de Zuma.

## Estado actual (2026-09-22)

Funcionando en el portátil (sin GPU, 11 GB de RAM):

- `nucleo-ia` (LiteLLM) en el puerto 4000, con red del host para alcanzar Ollama.
- Chat propio en el puerto 8080, servido con `python3 -m http.server`.
- Modelos mínimos: qwen2.5:0.5b, qwen2.5:1.5b, moondream.

Pruebas hechas:

| Prueba | Resultado |
|---|---|
| Texto | ✅ 1 s en caliente, 5,5 s la primera (carga el modelo) |
| Herramientas | ✅ Eligió `inventario_critico` con `limite: 10` |
| Visión | ✅ Leyó una imagen, con errores y en inglés (modelo de 1,8B) |
| Streaming | ✅ El texto llega palabra por palabra |

Conclusión: **el circuito sirve**. La calidad de estos modelos mínimos no, y eso se esperaba.

## Lo que sigue

1. Construir el enrutador por reglas (modelo único `zuma`).
2. Probar en la PC de 48 GB con modelos grandes (`config.yaml`: qwen2.5:7b / 14b / qwen2.5vl:7b).
3. Alquilar la A6000 por horas y levantar vLLM en vez de Ollama. Solo cambia `api_base`.
4. Conectar Zuma staging: `DEEPSEEK_BASE_URL` apunta aquí. La visión de Zuma necesita un cambio
   previo, porque tiene la URL fija en `OpenRouterService::OPENROUTER_ENDPOINT`.
5. Claves virtuales por proyecto con presupuesto, y luego cobro.

## Historia corta

Nació de una idea para Zuma: agentes IA que el dueño del restaurante pueda usar para controlar
todo (ver `docs/`), incluyendo subir una foto de la bodega para cargar el inventario. De ahí
salió la pregunta de si valía la pena Snowflake (respuesta: no para esto, es un almacén de datos
para análisis, no para operar) y de ahí la idea de tener plataforma propia.

## Relación con Zuma

El repo de Zuma está en `~/Saas-Restaurante`. Los documentos de los agentes viven en
`docs/agentes/` de ese repo; aquí se copiaron los tres que describen la plataforma.

## Pendiente: el chat del navegador no respondía (2026-09-22)

Estado al cerrar la sesión. Lo verificado:

- El gateway responde bien: una petición normal tarda **3,3 s** y el streaming entrega trozos.
- La página se sirve (`http.server` en el 8080) y el gateway acepta CORS desde ese origen.
- **La máquina está saturada:** carga 9,4 con 4 núcleos y ~200 MB de RAM libre, con los dos
  modelos cargados a la vez en CPU. Esa es la sospecha principal de la lentitud.

Para retomar:

1. Abrir la consola del navegador (F12 → Console y Network) y ver qué dice la petición a
   `localhost:4000`. Ahí se sabe si es CORS, la clave o simple lentitud.
2. Confirmar que la URL lleva `?key=...` (la clave está en `.env`).
3. `ollama stop qwen2.5:1.5b` para dejar un solo modelo cargado, y probar con `zuma-rapido`.
4. Si sigue lento: es la CPU. Pasar a la PC de 48 GB (`CONFIG_FILE=config.yaml`) o alquilar la
   GPU por horas.

`./arrancar.sh` levanta todo e imprime el link del chat con la clave ya puesta.
