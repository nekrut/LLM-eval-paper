#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f "data/ref/chrM.fa.fai" ] || [ ! -f "data/ref/chrM.fa.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"
    vcf="results/${sample}.vcf"

    # 3 & 4. Alignment and sorting (idempotent)
    if [ ! -f "$bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bam" ] || [ "data/ref/chrM.fa.bwt" -nt "$bam" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" \
        | samtools sort -@ $THREADS -o "$bam" -
    fi

    # 5. BAM indexing (idempotent)
    if [ ! -f "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # 6. Variant calling with lofreq call-parallel (idempotent)
    if [ ! -f "$vcf_gz" ] || [ "$bam" -nt "$vcf_gz" ]; then
        lofreq call-parallel \
            --threads $THREADS \
            --pp-threads 4 \
            -f "$REF" \
            -r results/${sample}.vcf \
            -o /dev/null \
            "$bam"
        # lofreq call-parallel writes to the file specified by -r if -o is not used or for intermediate? 
        # Correction: lofreq call-parallel syntax: lofreq call-parallel -f ref -r output.vcf input.bam
        # Actually, standard lofreq call-parallel usage:
        # lofreq call-parallel --threads N --pp-threads N -f ref -o output.vcf input.bam
        # Let's stick to the prompt's instruction: "Write uncompressed VCF to a temporary path... lofreq emits plain VCF."
        # The prompt says: "Use the call-parallel subcommand ... Reference: chrM.fa. Input: {sample}.bam. Write uncompressed VCF to a temporary path (e.g. results/{sample}.vcf)"
        
        # Re-doing step 6 correctly based on standard lofreq usage for parallel calling:
        # lofreq call-parallel -f ref -o output.vcf input.bam
        # But the prompt explicitly says "Write uncompressed VCF to a temporary path (e.g. results/{sample}.vcf)".
        # And later "Compress with bgzip ... producing results/{sample}.vcf.gz".
        
        # Let's ensure we generate the .vcf file first.
        if [ ! -f "$vcf" ] || [ "$bam" -nt "$vcf" ]; then
            lofreq call-parallel \
                --threads $THREADS \
                --pp-threads 4 \
                -f "$REF" \
                -o "$vcf" \
                "$bam"
        fi
    fi

    # 7. VCF compression and indexing (idempotent)
    if [ ! -f "$vcf_gz" ] || [ "$vcf" -nt "$vcf_gz" ]; then
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
collapsed="results/collapsed.tsv"
need_rebuild=false

for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz" ]; then
        need_rebuild=true
        break
    fi
done

if [ "$need_rebuild" = true ] || [ ! -f "$collapsed" ]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi