from app.models.models import (
    Base, User, Department, File, Permission, AuditLog,
    CopyTemplate, CopyHistory,
    # 3.1
    Customer, CustomerBehavior, CustomerSatisfaction,
    ChurnConfig, ChurnWarning, MarketingProposal,
    # 3.2
    MarketingProject, ProjectBrief, CommunityInteraction,
    CommunityDailyStat, KnowledgeEntry, QAChatRecord,
    # 3.3
    ContractTemplate, Contract, ContractVersion,
    BiddingKnowledgeDir, BiddingKnowledgeDoc,
    BiddingProcess, Supplier, Instructor,
    # Phase 4: PM
    PmProject, VisitLog, Courseware, ProjectReport,
    # Phase 4: HR
    Resume, Approval, ApprovalStep,
    # Phase 4: Interview
    Interview,
    # Phase 4: Finance
    Settlement, Expense, Voucher,
    # Phase 5: Finance upgrade
    Invoice, Payment, Budget,
)

__all__ = [
    "Base", "User", "Department", "File", "Permission", "AuditLog",
    "CopyTemplate", "CopyHistory",
    "Customer", "CustomerBehavior", "CustomerSatisfaction",
    "ChurnConfig", "ChurnWarning", "MarketingProposal",
    "MarketingProject", "ProjectBrief", "CommunityInteraction",
    "CommunityDailyStat", "KnowledgeEntry", "QAChatRecord",
    "ContractTemplate", "Contract", "ContractVersion",
    "BiddingKnowledgeDir", "BiddingKnowledgeDoc",
    "BiddingProcess", "Supplier", "Instructor",
    "PmProject", "VisitLog", "Courseware", "ProjectReport",
    "Resume", "Approval", "ApprovalStep",
    "Interview",
    "Settlement", "Expense", "Voucher",
    "Invoice", "Payment", "Budget",
]
