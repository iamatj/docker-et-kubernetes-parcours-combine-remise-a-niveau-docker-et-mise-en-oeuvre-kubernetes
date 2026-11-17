"""API de Huiteo RDV : prise de rendez-vous en ligne dans les études notariales.

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


journal = logging.getLogger("huiteo")
_sortie = logging.StreamHandler(sys.stdout)
_sortie.setFormatter(FormatJson())
journal.addHandler(_sortie)
journal.setLevel(logging.INFO)

# Études notariales clientes (fictives) : nom, ville, nombre de notaires, créneaux de rendez-vous par jour.
ETUDES = [
    ("Étude Martin et Associés", "Lyon", 4, 24),
    ("Office notarial du Parc", "Nantes", 2, 12),
    ("Étude Bernard-Roux", "Bordeaux", 3, 18),
    ("Étude des Halles", "Lille", 2, 10),
    ("Office notarial Saint-Michel", "Toulouse", 5, 30),
]


def connexion():
    return psycopg.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "huiteo"),
        user=os.environ.get("DB_USER", "huiteo"),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=2,
    )


def initialiser_base():
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            """CREATE TABLE IF NOT EXISTS etude (
                 id SERIAL PRIMARY KEY, nom TEXT UNIQUE NOT NULL, ville TEXT NOT NULL,
                 notaires INT NOT NULL, creneaux INT NOT NULL)"""
        )
        cur.execute(
            """CREATE TABLE IF NOT EXISTS rendez_vous (
                 id SERIAL PRIMARY KEY, etude_id INT NOT NULL REFERENCES etude(id),
                 nom TEXT NOT NULL, jour DATE NOT NULL, personnes INT NOT NULL,
                 creee_le TIMESTAMPTZ NOT NULL DEFAULT now())"""
        )
        for nom, ville, notaires, creneaux in ETUDES:
            cur.execute(
                "INSERT INTO etude (nom, ville, notaires, creneaux) VALUES (%s, %s, %s, %s) "
                "ON CONFLICT (nom) DO NOTHING",
                (nom, ville, notaires, creneaux),
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
        message=os.environ.get("MESSAGE_ACCUEIL", "Bienvenue sur Huiteo RDV"),
    )


@app.get("/api/etudes")
@schema_garanti
def etudes():
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            """SELECT e.id, e.nom, e.ville, e.notaires, e.creneaux, COUNT(r.id) AS pris
                 FROM etude e LEFT JOIN rendez_vous r ON r.etude_id = e.id
                GROUP BY e.id ORDER BY e.id"""
        )
        lignes = cur.fetchall()
    return jsonify([
        {"id": i, "nom": n, "ville": v, "notaires": no, "creneaux": c, "pris": int(p)}
        for i, n, v, no, c, p in lignes
    ])


@app.get("/api/rendez-vous")
@schema_garanti
def lister_rendez_vous():
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            """SELECT r.id, e.nom, r.nom, r.jour, r.personnes FROM rendez_vous r
                 JOIN etude e ON e.id = r.etude_id ORDER BY r.id DESC LIMIT 20"""
        )
        lignes = cur.fetchall()
    return jsonify([
        {"id": i, "etude": et, "nom": n, "jour": j.isoformat(), "personnes": p}
        for i, et, n, j, p in lignes
    ])


@app.post("/api/rendez-vous")
@schema_garanti
def prendre_rendez_vous():
    donnees = request.get_json(silent=True) or {}
    try:
        etude_id = int(donnees["etude_id"])
        personnes = int(donnees.get("personnes", 1))
        nom = str(donnees["nom"]).strip()[:80]
        jour = str(donnees["jour"])
    except (KeyError, ValueError, TypeError):
        return jsonify(erreur="etude_id, nom et jour sont obligatoires"), 400
    if not nom or personnes < 1:
        return jsonify(erreur="rendez-vous invalide"), 400
    with connexion() as cnx, cnx.cursor() as cur:
        cur.execute(
            "INSERT INTO rendez_vous (etude_id, nom, jour, personnes) VALUES (%s, %s, %s, %s) RETURNING id",
            (etude_id, nom, jour, personnes),
        )
        nouvel_id = cur.fetchone()[0]
    journal.info(f"rendez-vous {nouvel_id} : {personnes} pers. à l'étude {etude_id} le {jour}")
    return jsonify(id=nouvel_id), 201


demarrer()
