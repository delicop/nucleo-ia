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
| Enrutador | Por reglas + escalada, NO un modelo que clasifique (ver abajo). Va dentro del backend en Go |
| Backend | **Go**: un solo binario, poca RAM, bueno para streaming. Decidido el 2026-09-22 |
| Base de datos | **Postgres** en su propio contenedor, base `nucleo_ia`, volumen de Docker |
| Chat definitivo | **React + Vite**, compilado y embebido en el binario de Go. Estilo ChatGPT/Claude, marca Núcleo IA |

## Por qué no Open WebUI

Se probó el 2026-09-22 (contenedor `nucleo-chat`). **Sí llegaba al gateway**: los logs de
LiteLLM muestran sus peticiones con 200. Lo que falló fue todo lo demás:

- **Pesa demasiado para el portátil:** la imagen ocupa 6,5 GB y el contenedor carga su propio
  backend en Python, cuando la máquina ya estaba sin RAM libre.
- **Hace llamadas extra por cada mensaje** (título, etiquetas, sugerencias, autocompletar). En
  CPU cada una es otra respuesta del modelo en cola, y el chat parece colgado. Se apagaron con
  variables `ENABLE_*_GENERATION=false`, pero Open WebUI guarda esa configuración en su base
  la primera vez que arranca, así que las variables no siempre aplican después.
- **Falló por dentro:** en el log aparece `KeyError: 'model'` al generar el título, y la
  petición del chat terminó en `Server disconnected` / `Server Connection Error`.
- En la segunda prueba pasó igual: la pregunta quedó más de un minuto esperando al gateway,
  mientras el chat propio respondía en 1 s con el mismo modelo.

El chat propio (`chat/index.html`) hace una sola llamada por mensaje, no pesa nada y muestra
el error real cuando algo falla. Para un chat con marca de cara a clientes se puede volver a
mirar Open WebUI o LibreChat, ya en un servidor con GPU.

## Memoria entre chats

El chat de pruebas guarda las conversaciones en el navegador. Al preguntar, manda en la
instrucción de sistema lo que el usuario escribió en sus **otras** conversaciones (lo más
reciente primero, tope de 1.500 caracteres, ~400 tokens). Se apaga con "Recordar otros chats".

- No hace llamadas extra al modelo: en CPU cada llamada extra es otra espera (lo que hundió a
  Open WebUI).
- Solo usa los mensajes del usuario: ahí están los datos, y las respuestas ocupan mucho.
- Probado: sin historial en el chat, `zuma-rapido` y `zuma-chat` respondieron "La Brasa, 12
  mesas" a partir de la memoria.

Lo siguiente es guardarla en Postgres, en Núcleo IA y no en el navegador, para que la tengan
todos los proyectos y dispositivos (ver "Backend y base de datos").

## Backend y base de datos (decidido, por construir)

```
Navegador ──► Backend Go (chat + API + memoria + enrutador) ──► LiteLLM ──► Ollama / vLLM
                        │
                        └──► Postgres (usuarios, conversaciones, mensajes)
```

- **Todo queda guardado:** conversaciones y mensajes en Postgres, con volumen de Docker. Sobrevive
  a cerrar el chat, apagar Docker o reiniciar. Solo se borra con `docker compose down -v`.
- **Sin inventar:** se guarda el texto exacto de cada mensaje, y la memoria entre chats se arma
  con ese texto literal. Ningún modelo resume ni reescribe lo guardado.
- **Usuarios con login:** la memoria es de cada usuario, no una para todos.
- **Un solo contenedor** para el backend: sirve el chat (React compilado) y la API en el mismo
  puerto. El backend le habla a LiteLLM por HTTP.
- **Postgres propio**, aparte de los otros Postgres de la máquina, en un puerto libre y solo en
  `127.0.0.1`. La misma base le sirve después a LiteLLM para claves por proyecto y gastos.
- **Copia de seguridad:** el volumen no es respaldo; hace falta un `pg_dump` periódico.
- Funciones a llegar (como ChatGPT/Claude): editar un mensaje y regenerar, renombrar y buscar
  conversaciones, código con colores y botón de copiar.
- Quien mantenga el backend necesita saber Go.

`chat/index.html` queda como chat de pruebas hasta que el nuevo lo reemplace.

## El enrutador (pendiente de construir)

El proyecto pediría un solo modelo, `zuma`, y Núcleo IA decide:

| Lo que llega | A dónde va |
|---|---|
| Trae imagen | `zuma-vision` |
| Trae herramientas (`tools`) | `zuma-chat` |
| Texto corto y simple | `zuma-rapido` |
| El rápido falla o no puede | Reintenta en `zuma-chat` (escalada) |

No se usa el enrutador automático de LiteLLM: está en beta y el semántico quedó descontinuado.
Serían unas 60 líneas en Go, dentro del backend de Núcleo IA, no dentro de Zuma.

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

1. Construir el backend en Go + Postgres (ver "Backend y base de datos").
2. Construir el enrutador por reglas dentro del backend (modelo único `zuma`).
3. Chat definitivo en React, estilo ChatGPT/Claude, con login.
4. Probar en la PC de 48 GB con modelos grandes (`config.yaml`: qwen2.5:7b / 14b / qwen2.5vl:7b).
5. Alquilar la A6000 por horas y levantar vLLM en vez de Ollama. Solo cambia `api_base`.
6. Conectar Zuma staging: `DEEPSEEK_BASE_URL` apunta aquí. La visión de Zuma necesita un cambio
   previo, porque tiene la URL fija en `OpenRouterService::OPENROUTER_ENDPOINT`.
7. Claves virtuales por proyecto con presupuesto, y luego cobro.

## Historia corta

Nació de una idea para Zuma: agentes IA que el dueño del restaurante pueda usar para controlar
todo (ver `docs/`), incluyendo subir una foto de la bodega para cargar el inventario. De ahí
salió la pregunta de si valía la pena Snowflake (respuesta: no para esto, es un almacén de datos
para análisis, no para operar) y de ahí la idea de tener plataforma propia.

## Relación con Zuma

El repo de Zuma está en `~/Saas-Restaurante`. Los documentos de los agentes viven en
`docs/agentes/` de ese repo; aquí se copiaron los tres que describen la plataforma.

## Resuelto: el chat del navegador no respondía (2026-09-22)

El gateway y el CORS estaban bien. El chat mostraba "sin conexión" para cualquier error y la
máquina estaba saturada (dos modelos cargados y 12 contenedores de otros proyectos). El chat
ahora muestra el error real y responde en ~1 s con `zuma-rapido`. En el portátil: apagar los
otros contenedores antes de probar.

`./arrancar.sh` levanta todo e imprime el link del chat con la clave ya puesta.
