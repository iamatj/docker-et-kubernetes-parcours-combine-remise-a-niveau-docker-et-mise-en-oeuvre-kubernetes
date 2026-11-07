"""API de Cordée : réservation de nuitées dans les refuges de montagne.

Configuration par variables d'environnement :
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD  connexion PostgreSQL
  MESSAGE_ACCUEIL                                  bandeau affiché par le site
  APP_VERSION                                      version livrée (fixée au build)
  DELAI_DEMARRAGE                                  secondes d'attente simulées au démarrage (défaut 0)
  DB_ESSAIS                                        tentatives de connexion au démarrage (défaut 3)
"""
import functools
import json
import logging
import os
import socket
import sys
import time

import psycopg
from flask import Flask, jsonify, request

APP_VERSION = os.environ.get("APP_VERSION", "dev")
HOTE = socket.gethostname()


class FormatJson(logging.Formatter):
    def format(self, record):
        ligne = {
            "heure": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)),
            "niveau": record.levelname,
            "message": record.getMessage(),
            "version": APP_VERSION,
            "hote": HOTE,
        }
        return json.dumps(ligne, ensure_ascii=False)


journal = logging.getLogger("cordee")
_sortie = logging.StreamHandler(sys.stdout)
_sortie.setFormatter(FormatJson())
journal.addHandler(_sortie)
journal.setLevel(logging.INFO)

REFUGES = [
    ("Refuge de la Pra", "Belledonne", 2110, 60),
    ("Refuge du Goûter", "Mont-Blanc", 3835, 120),
    ("Refuge de l'Étendard", "Grandes Rousses", 2430, 50),
    ("Refuge des Bans", "Écrins", 2083, 40),
    ("Refuge de Font-Turbat", "Écrins", 2169, 35),
]


def connexion():
    return psycopg.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "cordee"),
        user=os.environ.get("DB_USER", "cordee"),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=2,
    )


def initialiser_base():
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            """CREATE TABLE IF NOT EXISTS refuge (
                 id SERIAL PRIMARY KEY, nom TEXT UNIQUE NOT NULL, massif TEXT NOT NULL,
                 altitude INT NOT NULL, places INT NOT NULL)"""
        )
        cur.execute(
            """CREATE TABLE IF NOT EXISTS reservation (
                 id SERIAL PRIMARY KEY, refuge_id INT NOT NULL REFERENCES refuge(id),
                 nom TEXT NOT NULL, nuit DATE NOT NULL, personnes INT NOT NULL,
                 creee_le TIMESTAMPTZ NOT NULL DEFAULT now())"""
        )
        for nom, massif, altitude, places in REFUGES:
            cur.execute(
                "INSERT INTO refuge (nom, massif, altitude, places) VALUES (%s, %s, %s, %s) "
                "ON CONFLICT (nom) DO NOTHING",
                (nom, massif, altitude, places),
            )


def demarrer():
    delai = int(os.environ.get("DELAI_DEMARRAGE", "0"))
    if delai:
        journal.info(f"démarrage lent simulé : {delai} s")
        time.sleep(delai)
    essais = int(os.environ.get("DB_ESSAIS", "3"))
    for essai in range(1, essais + 1):
        try:
            initialiser_base()
            journal.info("base de données prête")
            return
        except psycopg.OperationalError as erreur:
            journal.error(f"base injoignable (essai {essai}/{essais}) : {str(erreur).strip()}")
            time.sleep(1)
    journal.error("abandon : impossible de joindre la base de données")
    sys.exit(1)


def schema_garanti(vue):
    """Si la base a été recréée vide (pod PostgreSQL sans volume), recrée les tables et réessaie une fois."""
    @functools.wraps(vue)
    def enveloppe(*args, **kwargs):
        try:
            return vue(*args, **kwargs)
        except psycopg.errors.UndefinedTable:
            journal.warning("tables absentes : la base a été recréée vide, initialisation")
            initialiser_base()
            return vue(*args, **kwargs)
    return enveloppe


app = Flask(__name__)


@app.get("/healthz")
def vivant():
    return jsonify(statut="ok")


@app.get("/readyz")
def pret():
    try:
        with connexion() as cnx:
            cnx.execute("SELECT 1")
        return jsonify(statut="prêt")
    except psycopg.Error as erreur:
        journal.warning(f"pas prêt : {str(erreur).strip()}")
        return jsonify(statut="base injoignable"), 503


@app.get("/api/info")
def info():
    return jsonify(
        version=APP_VERSION,
        hote=HOTE,
        message=os.environ.get("MESSAGE_ACCUEIL", "Bienvenue sur Cordée"),
    )


@app.get("/api/refuges")
@schema_garanti
def refuges():
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            """SELECT r.id, r.nom, r.massif, r.altitude, r.places,
                      COALESCE(SUM(b.personnes), 0) AS reservees
                 FROM refuge r LEFT JOIN reservation b ON b.refuge_id = r.id
                GROUP BY r.id ORDER BY r.id"""
        )
        lignes = cur.fetchall()
    return jsonify([
        {"id": i, "nom": n, "massif": m, "altitude": a, "places": p, "reservees": int(r)}
        for i, n, m, a, p, r in lignes
    ])


@app.get("/api/reservations")
@schema_garanti
def lister_reservations():
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            """SELECT b.id, r.nom, b.nom, b.nuit, b.personnes FROM reservation b
                 JOIN refuge r ON r.id = b.refuge_id ORDER BY b.id DESC LIMIT 20"""
        )
        lignes = cur.fetchall()
    return jsonify([
        {"id": i, "refuge": rf, "nom": n, "nuit": nu.isoformat(), "personnes": p}
        for i, rf, n, nu, p in lignes
    ])


@app.post("/api/reservations")
@schema_garanti
def reserver():
    donnees = request.get_json(silent=True) or {}
    try:
        refuge_id = int(donnees["refuge_id"])
        personnes = int(donnees.get("personnes", 1))
        nom = str(donnees["nom"]).strip()[:80]
        nuit = str(donnees["nuit"])
    except (KeyError, ValueError, TypeError):
        return jsonify(erreur="refuge_id, nom et nuit sont obligatoires"), 400
    if not nom or personnes < 1:
        return jsonify(erreur="réservation invalide"), 400
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            "INSERT INTO reservation (refuge_id, nom, nuit, personnes) VALUES (%s, %s, %s, %s) RETURNING id",
            (refuge_id, nom, nuit, personnes),
        )
        nouvel_id = cur.fetchone()[0]
    journal.info(f"réservation {nouvel_id} : {personnes} pers. au refuge {refuge_id} le {nuit}")
    return jsonify(id=nouvel_id), 201


demarrer()
