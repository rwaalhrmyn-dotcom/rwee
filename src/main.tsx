import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import './styles.css'
import Layout from './components/Layout'
import Home from './pages/Home'
import Products from './pages/Products'
import Suppliers from './pages/Suppliers'
import Cart from './pages/Cart'
import NotFound from './pages/NotFound'
import CustomerLogin from './pages/customer/CustomerLogin'
import CustomerHome from './pages/customer/CustomerHome'
import SupplierLogin from './pages/supplier/SupplierLogin'
import SupplierHome from './pages/supplier/SupplierHome'
import AdminLogin from './pages/admin/AdminLogin'
import AdminHome from './pages/admin/AdminHome'
import Checkout from './pages/Checkout'
import SupplierRegister from './pages/supplier/SupplierRegister'
import SupplierInventory from './pages/supplier/SupplierInventory'
import SupplierOrders from './pages/supplier/SupplierOrders'
import AdminDashboard from './pages/admin/AdminDashboard'
import OrderDetail from './pages/customer/OrderDetail'
import Loyalty from './pages/customer/Loyalty'
import SupplierContract from './pages/supplier/SupplierContract'
import ProductForm from './pages/supplier/ProductForm'
import Shipping from './pages/supplier/Shipping'
import Gifts from './pages/Gifts'
import ImportProducts from './pages/supplier/ImportProducts'
import Terms from './pages/Terms'
import Bundles from './pages/Bundles'
import Business from './pages/Business'
import Needs from './pages/Needs'
import DeliveryDocs from './pages/customer/DeliveryDocs'
import CompareSuppliers from './pages/CompareSuppliers'
import { CartProvider } from './context/CartContext'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <CartProvider>
      <BrowserRouter>
        <Routes>
          <Route element={<Layout />}>
            <Route path="/" element={<Home />} />
            <Route path="/products" element={<Products />} />
            <Route path="/suppliers" element={<Suppliers />} />
            <Route path="/cart" element={<Cart />} />
            <Route path="/customer" element={<CustomerHome />} />
            <Route path="/customer/login" element={<CustomerLogin />} />
            <Route path="/supplier" element={<SupplierHome />} />
            <Route path="/supplier/login" element={<SupplierLogin />} />
            <Route path="/admin" element={<AdminHome />} />
            <Route path="/admin/login" element={<AdminLogin />} />
            <Route path="/checkout" element={<Checkout />} />
            <Route path="/supplier/register" element={<SupplierRegister />} />
            <Route path="/supplier/inventory" element={<SupplierInventory />} />
            <Route path="/supplier/orders" element={<SupplierOrders />} />
            <Route path="/admin/dashboard" element={<AdminDashboard />} />
            <Route path="/customer/orders/:id" element={<OrderDetail />} />
            <Route path="/loyalty" element={<Loyalty />} />
            <Route path="/supplier/contract" element={<SupplierContract />} />
            <Route path="/supplier/products/new" element={<ProductForm />} />
            <Route path="/supplier/shipping" element={<Shipping />} />
            <Route path="/gifts" element={<Gifts />} />
            <Route path="/sadaqah" element={<Gifts />} />
            <Route path="/supplier/import" element={<ImportProducts />} />
            <Route path="/terms" element={<Terms />} />
            <Route path="/privacy" element={<Terms />} />
            <Route path="/bundles" element={<Bundles />} />
            <Route path="/business" element={<Business />} />
            <Route path="/needs" element={<Needs />} />
            <Route path="/delivery" element={<DeliveryDocs />} />
            <Route path="/customer/delivery" element={<DeliveryDocs />} />
            <Route path="/compare" element={<CompareSuppliers />} />
            <Route path="*" element={<NotFound />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </CartProvider>
  </React.StrictMode>,
)
