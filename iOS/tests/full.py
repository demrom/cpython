import os
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
from io import StringIO

import numpy as np
from sklearn import show_versions
from sklearn.cluster import KMeans
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.linear_model import LinearRegression
from sklearn.neighbors import NearestNeighbors

versions = StringIO()
with redirect_stdout(versions):
    show_versions()
assert "Built with OpenMP: True" in versions.getvalue()
with ThreadPoolExecutor(max_workers=2) as pool:
    for result in pool.map(np.sin, (np.array([0.0, np.pi / 2, np.pi, 3 * np.pi / 2]),) * 2):
        np.testing.assert_allclose(result, [0.0, 1.0, 0.0, -1.0], atol=1e-15)
model = LinearRegression(n_jobs=2).fit([[0.0], [1.0], [2.0]], [1.0, 3.0, 5.0])
np.testing.assert_allclose(model.predict([[3.0]]), [7.0])
groups = KMeans(n_clusters=2, n_init=1, random_state=0).fit_predict([[0.0], [0.1], [10.0], [10.1]])
assert groups[0] == groups[1] and groups[2] == groups[3] and groups[0] != groups[2]
neighbors = NearestNeighbors(n_neighbors=1, n_jobs=2).fit([[0.0], [10.0]])
np.testing.assert_array_equal(neighbors.kneighbors([[9.0]], return_distance=False), [[1]])
gradient = HistGradientBoostingRegressor(min_samples_leaf=1, max_iter=3, random_state=0).fit([[0.0], [1.0], [2.0], [3.0]], [0.0, 1.0, 2.0, 3.0])
assert np.isfinite(gradient.predict([[1.5]])).all()
print("Scikit-learn parallel estimators and NumPy worker ufuncs PASS", flush=True)

import zmq

baseline = len(os.listdir("/dev/fd"))
for iteration in range(2):
    with zmq.Context() as context:
        with context.socket(zmq.PAIR) as sender, context.socket(zmq.PAIR) as receiver:
            sender.setsockopt(zmq.LINGER, 0)
            receiver.setsockopt(zmq.LINGER, 0)
            receiver.setsockopt(zmq.RCVTIMEO, 2000)
            endpoint = f"inproc://full-package-{iteration}"
            sender.bind(endpoint)
            receiver.connect(endpoint)
            payload = "Python ZMQ roundtrip: café".encode()
            sender.send(payload)
            assert receiver.recv() == payload
assert len(os.listdir("/dev/fd")) == baseline
print("PyZMQ CFFI PAIR bytes and descriptor cleanup PASS", flush=True)
