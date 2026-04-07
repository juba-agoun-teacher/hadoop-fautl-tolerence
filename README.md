# TP Hadoop – HDFS, MapReduce & Tolérance aux Pannes avec Docker

> **Travaux Pratiques – Systèmes Distribués**  
> Infrastructure Docker · HDFS · MapReduce · Fault Tolerance

---



## Architecture du cluster

```
┌──────────────────────────────────────────────────────────┐
│                      Docker Network                      │
│                    (172.20.0.0/16)                       │
│                                                          │
│  ┌─────────────────────────────┐                         │
│  │      namenode (Master)      │  172.20.0.2             │
│  │  ─ NameNode  (HDFS)         │  :9870  → Web UI HDFS   │
│  │  ─ ResourceManager (YARN)   │  :8088  → Web UI YARN   │
│  └───────────────┬─────────────┘                         │
│                  │                                       │
│       ┌──────────┼──────────────┐                        │
│       ▼          ▼              ▼                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                  │
│  │datanode1 │ │datanode2 │ │datanode3 │                  │
│  │172.20.0.3│ │172.20.0.4│ │172.20.0.5│                  │
│  │DataNode  │ │DataNode  │ │DataNode  │                  │
│  │NodeMgr   │ │NodeMgr   │ │NodeMgr   │                  │
│  └──────────┘ └──────────┘ └──────────┘                  │
└──────────────────────────────────────────────────────────┘
```

<!-- ; | Conteneur   | Rôle                          | Port exposé          |
; |-------------|-------------------------------|----------------------|
; | `namenode`  | NameNode + ResourceManager    | 9870 (HDFS), 8088 (YARN) |
; | `datanode1` | DataNode + NodeManager        | —                    |
; | `datanode2` | DataNode + NodeManager        | —                    |
; | `datanode3` | DataNode + NodeManager        | —                    | -->

---

## 📁 Structure du projet

```
hadoop-tp/
├── docker-compose.yml          # Définition du cluster
├── hadoop-config/
│   ├── core-site.xml           # Configuration HDFS (URI du cluster)
│   ├── hdfs-site.xml           # Réplication, taille des blocs
│   ├── mapred-site.xml         # Framework MapReduce
│   ├── yarn-site.xml           # Gestionnaire de ressources
│   └── workers                 # Liste des DataNodes
├── data/
│   └── generate_ratings.py     # Générateur de dataset
├── mapreduce/
│   ├── mapper_ratings.py       # Mapper Hadoop Streaming
│   └── reducer_ratings.py      # Reducer Hadoop Streaming
├── scripts/
│   └── tp_hadoop.sh            # Script principal du TP
└── README.md
```

---
<!-- 
; ## ⚙️ Prérequis

; | Outil          | Version minimale | Vérification         |
; |----------------|-----------------|----------------------|
; | Docker Desktop | 24+             | `docker --version`   |
; | Docker Compose | 2.20+           | `docker compose version` |
; | Python 3       | 3.8+            | `python3 --version`  |
; | Git            | 2.x             | `git --version`      | -->

; > **Ressources recommandées :** ≥ 8 Go de RAM disponibles pour Docker

---

## Partie 1 – Lancement et manipulation HDFS

### Étape 0 — Cloner et démarrer le cluster

```bash
# 1. Cloner le dépôt ou télécharger le repo
git clone ....

```bash
# Aller dans le dossier
```
```bash
# 2. Démarrer les 4 conteneurs
docker compose up -d
```
```bash
# 3. Vérifier que les conteneurs sont bien lancés
docker compose ps
```

**Sortie attendue :**
```
NAME         STATUS
namenode     Up (healthy)
datanode1    Up
datanode2    Up
datanode3    Up
```

Attendez environ **30 secondes** que le NameNode initialise HDFS, puis ouvrez les interfaces Web :

- **HDFS Web UI** → http://localhost:9870
- **YARN Web UI** → http://localhost:8088

> 💡 Dans l'onglet *"Datanodes"* du HDFS Web UI, vous devez voir **3 nœuds actifs**.

---

### Étape 1 — Générer le fichier de ratings en local

Le dataset est inspiré du format **MovieLens** (userId, movieId, rating, timestamp).

```bash
# Entrer dans le conteneur namenode
docker exec -it namenode bash

# Générer 100 000 ratings
python3 /data/generate_ratings.py 100000

# Vérifier le fichier
wc -l /data/ratings.csv
head -5 /data/ratings.csv
```

**Sortie attendue :**
```
100001 /data/ratings.csv   ← (100 000 lignes + header)
userId,movieId,rating,timestamp
4,2814,3.5,1623451234
...
```

#### Questions – Étape 1

1. Quelle est la taille du fichier `ratings.csv` en Mo ? 
> Votre commande

2. Combien de notes distinctes y a-t-il dans le fichier ? 
> Votre commande

---

### Étape 2 — Copier le fichier dans HDFS


- Dans le conteneur namenode

- Créer l'arborescence dans HDFS un dossier ratings dans /user/tp

> votre commande

- Copier le fichier local vers HDFS
 
> votre commande

- Vérifier la présence du fichier
> votre commande
- Afficher la taille

> votre commande


#### Inspecter les blocs HDFS


- Quelle est la  répartition des blocs sur les DataNodes avec ``fsck`` et les arguments ``-blocks -locations``
> votre commande

**Sortie typique :**
```
/user/tp/ratings/ratings.csv ...
 Block 0: blk_1234... len=134217728
   [DatanodeInfoWithStorage[172.20.0.3, datanode1, DISK],
    DatanodeInfoWithStorage[172.20.0.4, datanode2, DISK],
    DatanodeInfoWithStorage[172.20.0.5, datanode3, DISK]]
```

#### 🔍 Questions – Étape 2

1. Combien de blocs HDFS occupe le fichier ? Pourquoi ?
2. Quelle est la taille d'un bloc par défaut dans notre configuration ?
3. Sur combien de DataNodes chaque bloc est-il répliqué ? Quel paramètre contrôle cela ?
4. Retrouvez ces informations dans le HDFS Web UI : `http://localhost:9870/explorer.html`

---

### Étape 3 — Traitement MapReduce : comptage des ratings

Nous allons compter combien de fois chaque note (0.5, 1.0, ..., 5.0) apparaît dans le dataset, en utilisant **Hadoop** (MapReduce en Python).

<!-- #### Architecture du job MapReduce

```
ratings.csv (HDFS)
       │
       ▼ (split en blocs)
┌──────────────────────────────────────┐
│  PHASE MAP                           │
│  mapper_ratings.py                   │
│  Entrée : userId,movieId,rating,...  │
│  Sortie : "3.5" → 1                 │
│           "4.0" → 1                 │
│           "3.5" → 1  ...            │
└──────────────┬───────────────────────┘
               │ (shuffle & sort par clé)
               ▼
┌──────────────────────────────────────┐
│  PHASE REDUCE                        │
│  reducer_ratings.py                  │
│  Entrée : "3.5" → [1,1,1,...]       │
│  Sortie : "3.5" → 24 831            │
└──────────────────────────────────────┘
       │
       ▼
output/ (HDFS)
``` -->

#### Lancement du job

```bash
# Dans le conteneur namenode

# Trouver le JAR Hadoop Streaming
STREAMING_JAR=$(find /opt/hadoop/share/hadoop/tools/lib/ -name "hadoop-streaming*.jar" | head -1)
echo "JAR : $STREAMING_JAR"

# Supprimer l'éventuel répertoire de sortie précédent
hdfs dfs -rm -r -f /user/tp/output_ratings

# Lancer le job
hadoop jar $STREAMING_JAR \
  -input  /user/tp/ratings/ratings.csv \
  -output /user/tp/output_ratings \
  -mapper  "python3 /mapreduce/mapper_ratings.py" \
  -reducer "python3 /mapreduce/reducer_ratings.py" \
  -file /mapreduce/mapper_ratings.py \
  -file /mapreduce/reducer_ratings.py
```

#### Lire les résultats

```bash
# Afficher les résultats triés
hdfs dfs -cat /user/tp/output_ratings/part-* | sort -t$'\t' -k1 -n
```

**Sortie attendue :**
```
0.5     9823
1.0     9978
1.5     10102
2.0     10050
2.5     9987
3.0     10064
3.5     9956
4.0     10091
4.5     9973
5.0     9976
```

> 💡 Suivez l'avancement du job en temps réel sur **YARN** : http://localhost:8088

#### Questions – Étape 3

1. Combien de tâches Map ont été créées ? Pourquoi ce nombre ?
2. Combien de tâches Reduce ? Quel paramètre permet d'en avoir plusieurs ?
3. Que se passe-t-il dans la phase *Shuffle & Sort* entre Map et Reduce ?
4. Quelle note est la plus fréquente dans votre dataset ?
5. Testez le mapper localement sans Hadoop :
   ```bash
   head -100 /data/ratings.csv | python3 /mapreduce/mapper_ratings.py | sort | python3 /mapreduce/reducer_ratings.py
   ```

---

### Étape 4 — Impact de la taille des blocs

Nous allons uploader le même fichier avec **3 tailles de blocs différentes** et mesurer l'impact sur le nombre de blocs et la durée du job.

```bash
# Dans le conteneur namenode

STREAMING_JAR=$(find /opt/hadoop/share/hadoop/tools/lib/ -name "hadoop-streaming*.jar" | head -1)

for BLOCK_MB in 64 128 256; do
  BLOCK_BYTES=$(( BLOCK_MB * 1024 * 1024 ))
  echo ""
  echo "════════════════════════════════════"
  echo "  Test avec blocs de ${BLOCK_MB} Mo"
  echo "════════════════════════════════════"

  # Upload avec la taille de bloc choisie
  hdfs dfs -mkdir -p /user/tp/ratings_block${BLOCK_MB}m
  hdfs dfs -D dfs.blocksize=${BLOCK_BYTES} \
    -put -f /data/ratings.csv /user/tp/ratings_block${BLOCK_MB}m/ratings.csv

  # Nombre de blocs
  echo "Blocs utilisés :"
  hdfs fsck /user/tp/ratings_block${BLOCK_MB}m/ratings.csv \
    -files -blocks 2>/dev/null | grep "Total blocks"

  # Job MapReduce avec mesure du temps
  hdfs dfs -rm -r -f /user/tp/output_block${BLOCK_MB}m
  START=$(date +%s)
  hadoop jar $STREAMING_JAR \
    -D dfs.blocksize=${BLOCK_BYTES} \
    -input  /user/tp/ratings_block${BLOCK_MB}m/ratings.csv \
    -output /user/tp/output_block${BLOCK_MB}m \
    -mapper  "python3 /mapreduce/mapper_ratings.py" \
    -reducer "python3 /mapreduce/reducer_ratings.py" \
    -file /mapreduce/mapper_ratings.py \
    -file /mapreduce/reducer_ratings.py \
    2>&1 | grep -E "(map|reduce|Completed)"
  END=$(date +%s)
  echo "Durée : $(( END - START )) secondes"
done
```

#### Tableau de résultats à remplir

| Taille du bloc | Nb de blocs | Nb tâches Map | Durée du job |
|:--------------:|:-----------:|:-------------:|:------------:|
| 64 Mo          | ?           | ?             | ? s          |
| 128 Mo         | ?           | ?             | ? s          |
| 256 Mo         | ?           | ?             | ? s          |

#### Questions – Étape 4

1. Quelle relation observez-vous entre la taille des blocs et le nombre de tâches Map ?
2. Avec un fichier très petit (< 1 Mo), quel problème pose une grande taille de bloc ?

---

## Partie 2 – Tolérance aux Pannes

> **Objectif :** Observer comment HDFS et YARN réagissent à la perte d'un DataNode.

### Étape 5 — État initial du cluster

```bash
# Dans le conteneur namenode

# Vue d'ensemble
hdfs dfsadmin -report

# Santé du fichier de ratings
hdfs fsck /user/tp/ratings/ratings.csv -files -blocks -locations 2>/dev/null | head -30
```

Notez l'état initial :
- Nombre de DataNodes actifs : **___**
- Nombre de blocs du fichier : **___**
- Facteur de réplication effectif : **___**

---

### Étape 6 — Simuler une panne (arrêt de datanode1)

**Sur votre terminal HOST** (pas dans un conteneur) :

```bash
# Arrêter brusquement datanode1 (simule une panne matérielle)
docker stop datanode1
```

**Dans le conteneur namenode**, observez la réaction :

```bash
# Attendre la détection (le NameNode a un délai de heartbeat)
sleep 30

# Observer les DataNodes actifs
hdfs dfsadmin -report | grep -E "^(Live|Dead|Decommission)"

# Santé du système de fichiers
hdfs fsck /user/tp/ratings/ratings.csv | grep -E "(Status|replicat|corrupt|missing|Under)"
```

> ⚠️ Le NameNode détecte la panne après **~30 secondes** (timeout heartbeat).  
> Vous devriez voir le fichier signalé comme **"Under replicated"** (sous-répliqué).

---

### Étape 7 — Vérifier la continuité de service

**Le cluster doit rester opérationnel avec 2 DataNodes !**

```bash
# Dans le conteneur namenode

# Test 1 : lecture HDFS
echo "Test lecture HDFS :"
hdfs dfs -cat /user/tp/ratings/ratings.csv | wc -l

# Test 2 : nouveau job MapReduce pendant la panne
echo ""
echo "Lancement d'un job MapReduce avec 2 DataNodes actifs..."
STREAMING_JAR=$(find /opt/hadoop/share/hadoop/tools/lib/ -name "hadoop-streaming*.jar" | head -1)
hdfs dfs -rm -r -f /user/tp/output_panne
hadoop jar $STREAMING_JAR \
  -input  /user/tp/ratings/ratings.csv \
  -output /user/tp/output_panne \
  -mapper  "python3 /mapreduce/mapper_ratings.py" \
  -reducer "python3 /mapreduce/reducer_ratings.py" \
  -file /mapreduce/mapper_ratings.py \
  -file /mapreduce/reducer_ratings.py

# Vérifier que les résultats sont corrects
hdfs dfs -cat /user/tp/output_panne/part-* | sort -t$'\t' -k1 -n
```



## Rappel des commandes essentielles

```bash
# ── Docker ──────────────────────────────────────────────────
docker compose up -d               # Démarrer le cluster
docker compose ps                  # État des conteneurs
docker exec -it namenode bash      # Entrer dans le namenode
docker stop datanode1              # Simuler une panne
docker start datanode1             # Restaurer un nœud
docker compose down -v             # Tout supprimer

# ── HDFS ────────────────────────────────────────────────────
hdfs dfs -mkdir -p /chemin         # Créer un répertoire
hdfs dfs -put fichier /hdfs/path   # Uploader un fichier
hdfs dfs -ls /chemin               # Lister
hdfs dfs -cat /chemin/fichier      # Lire un fichier
hdfs dfs -rm -r /chemin            # Supprimer
hdfs dfs -du -s -h /chemin        # Taille
hdfs fsck /chemin -files -blocks   # Santé des blocs
hdfs dfsadmin -report              # État du cluster

# ── MapReduce ───────────────────────────────────────────────
hadoop jar hadoop-streaming.jar \
  -input /hdfs/input \
  -output /hdfs/output \
  -mapper mapper.py \
  -reducer reducer.py

# ── YARN ────────────────────────────────────────────────────
yarn application -list             # Jobs en cours
yarn logs -applicationId <id>      # Logs d'un job
```

---


**Bonne chance ! 🐘**

*N'hésitez pas à ouvrir une issue si vous rencontrez un problème.*

</div>
